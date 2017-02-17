#pragma semicolon 1
#define DEBUG //Uncomment this to enable debug prints to server console.

char chatPrefix[32];

#define questionSize 64
#define QUESTION 0
#define OPTIONA  1
#define OPTIONB  2
//ArrayList alAskingQuestions[MAXPLAYERS+1];
//bool plySelectedCategories[MAXPLAYERS+1][MAX_CAT]; //Temporarily stores if the player has selected this category.

//Database stuff:
bool dbiLoaded = false;
bool useDBI = false;
bool useMySQL = false;
Database dbStats;

//ConVar cRandom;
//ConVar cSpacer;

#define PLUGIN_VERSION "1.1.0"
public Plugin myinfo = {
	name = "Would You Rather..",
	author = "Mitch",
	description = "A simple would you rather game.",
	version = PLUGIN_VERSION,
	url = "http://mtch.tech"
};

public OnPluginStart() {
	getChatPrefix(chatPrefix, sizeof(chatPrefix));

	CreateConVar("sm_wouldyourather_version", PLUGIN_VERSION, "Version of Would You Rather plugin", FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	//cRandom = CreateConVar("sm_wouldyourather_random", "1", "Randomize the order of the questions before showing the client.");
	//cSpacer = CreateConVar("sm_wouldyourather_menuspacer", "1", "0 For no menu spacer when being asked questions, 1 For menu spacers and the text 'Or...'");
	AutoExecConfig(true, "WouldYouRather");

	//RegConsoleCmd("sm_wyr", Command_WouldYouRather);
	//RegConsoleCmd("sm_wouldyourather", Command_WouldYouRather);

	connectToDatabase();
	
	/*for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}*/
}

public void getChatPrefix(char[] prefix, int size) {
	if(GetEngineVersion() == Engine_CSGO) {
		Format(prefix, size, " \x08[\x0CWYR\x08]\x01");
	} else {
		Format(prefix, size, "\x07898989[\x07216fedWYR\x07898989]\x01");
	}
}

public void connectToDatabase() {
	dbiLoaded = false;
	if(SQL_CheckConfig("wouldyourather")) {
		Database.Connect(dbConnect, "wouldyourather");
	} else {
		SetFailState("Database config for 'wouldyourather' not found. See README for setup guide.");
	}
}

/*
Tables:
players - accountId, name, steam64
answers - accountId, questionId, answered, time
questions - questionId, category, description, question, option1, option2
*/
public void dbConnect(Database db, const char[] error, any data) {
	if(db == null) {
		LogMessage("Database failure: %s", error);
	} else {
		useDBI = true;
		dbStats = db;
		DBDriver driver = db.Driver;
		char sDriver[32];
		driver.GetIdentifier(sDriver, sizeof(sDriver));
		useMySQL = StrEqual(sDriver, "mysql", false);
		
		Transaction transaction = new Transaction();
		if(useMySQL) {
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `players` (`accountid` int(32) NOT NULL, `name` varchar(128) NOT NULL, `steam64` varchar(64) NOT NULL, PRIMARY KEY (`accountid`));");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `answers` (`accountid` int(32) NOT NULL, `questionid` int(32) NOT NULL, `answered` int(32) NOT NULL, `time` int(64) DEFAULT 0);");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `questions` (`questionid` int(32) AUTO_INCREMENT, `category` varchar(64) NOT NULL, `question` varchar(64) NOT NULL, `option1` varchar(64) NOT NULL, `option2` varchar(64) NOT NULL, `addedby` int(32) DEFAULT 0, PRIMARY KEY (`questionid`), UNIQUE(`category`, `question`, `option1`, `option2`));");
		} else {
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `players` (`accountid` int(32) NOT NULL, `name` varchar(128) NOT NULL, `steam64` varchar(64) NOT NULL, PRIMARY KEY (`accountid`))");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `answers` (`accountid` int(32) NOT NULL, `questionid` int(32) NOT NULL, `answered` int(32) NOT NULL, `time` int(64) DEFAULT 0)");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `questions` (`questionid` INTEGER PRIMARY KEY AUTOINCREMENT, `category` varchar(64) PRIMARY KEY NOT NULL, `question` varchar(64) PRIMARY KEY NOT NULL, `option1` varchar(64) PRIMARY KEY PRIMARY KEY NOT NULL, `option2` varchar(64) PRIMARY KEY NOT NULL, PRIMARY KEY (`questionid`, `category`, `question`, `option1`, `option2`));");
		}
		dbStats.Execute(transaction, connectOnSuccess, threadFailure);
	}
}

public void threadFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	LogError("Error in Database Execution: %s", error);
}

public void connectOnSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	dbiLoaded = true;
	loadQuestions();
	loadAllPlayers();
}

bool plyInDatabase[MAXPLAYERS+1];

public void loadAllPlayers() {
	Transaction transaction = new Transaction();
	for(int i = 1; i <= MaxClients; i++) {
		loadPlayer(i, transaction);
	}
	dbStats.Execute(transaction, loadPlayerOnSuccess, threadFailure);
}

public void loadPlayer(int client, Transaction trans) {
	if(dbiLoaded != true || client <= 0 || !IsClientInGame(client)) {
		return;
	}
	Transaction transaction = (trans != null) ? trans : new Transaction();
	char sqlBuffer[256];
	int userId = GetClientUserId(client);
	int accountId = GetSteamAccountID(client);
	dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "SELECT name FROM players WHERE accountid='%i'", accountId);
	transaction.AddQuery(sqlBuffer, userId);
	//The player should only exist in the database if they have played the game before, otherwise why store their information?
	if(trans == null) {
		dbStats.Execute(transaction, loadPlayerOnSuccess, threadFailure);
	}
}

public void loadPlayerOnSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	int client;
	char clientName[128];
	for(int x = 0; x < numQueries; x++) {
		client = GetClientOfUserId(queryData[x]);
		if(client <= 0) {
			continue;
		}
		if(results[x].RowCount > 0) {
			char tempName[128];
			while(results[x].FetchRow()) {
				results[x].FetchString(0, tempName, sizeof(tempName));
			}
			GetClientName(client, clientName, sizeof(clientName));
			if(!StrEqual(clientName, tempName)) {
				//If the player already exists then update their name.
				//updatePlayerName(client, clientName);
			}
		}
	}
}

public void loadQuestions() {
	if(dbStats == null) {
		return;
	}
	char directoryPath[PLATFORM_MAX_PATH];
	char fullPath[PLATFORM_MAX_PATH];
	char fileName[PLATFORM_MAX_PATH];
	char tempBuffer[(questionSize*3)+2];
	char splitBuffer[3][questionSize];
	int count;
	File file;
	FileType fileType;

	BuildPath(Path_SM, directoryPath, sizeof(directoryPath), "configs/WouldYouRather");
	if(!DirExists(directoryPath)) {
		SetFailState("Config folder not found: %s", directoryPath);
	}

	char sqlBuffer[512];
	Transaction transaction = new Transaction();
	DirectoryListing directoryListing = OpenDirectory(directoryPath, false);
	while(directoryListing.GetNext(fullPath, sizeof(fullPath), fileType)) {
		if(fileType != FileType_File) {
			continue;
		}
		//There is no longer a cap on categories :)
		/*if(confCategory >= MAX_CAT) {
			LogError("Hit the max category limit of %i categories, ignoring the rest.", MAX_CAT);
			break;
		}*/
		strcopy(fileName, sizeof(fileName), fullPath);
		Format(fullPath, sizeof(fullPath), "%s/%s", directoryPath, fullPath);
		ReplaceString(fileName, sizeof(fileName), ".cfg", "");
		ReplaceString(fileName, sizeof(fileName), ".txt", "");

		#if defined DEBUG
		PrintToServer("Opening file: %s", fullPath);
		#endif

		file = OpenFile(fullPath, "r");
		while(file.ReadLine(tempBuffer, sizeof(tempBuffer))) {
			TrimString(tempBuffer);
			count = ExplodeString(tempBuffer, "|", splitBuffer, 3, questionSize, false);
			if(count != 3) {
				//A delimiter was missing or an extra delimiter was found, which means the config might be missing an option, which will screw up the plugin.
				LogError("Config incorrectly configured, delimiter incorrectly defined.");
				LogError("  file: %s", fullPath);
				LogError("  line: %s", tempBuffer);
				SetFailState("Config errors found, please revise the config (see error logs for file and line).");
			}
			dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "INSERT IGNORE INTO questions (category, question, option1, option2) VALUES ('%s', '%s', '%s', '%s');", fileName, splitBuffer[0], splitBuffer[1], splitBuffer[2]);
			transaction.AddQuery(sqlBuffer);
		}
		file.Close();
	}
	dbStats.Execute(transaction, loadQuestionsOnSuccess, threadFailure);
}

public void loadQuestionsOnSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	#if defined DEBUG
	PrintToServer("Loaded questions into sql.");
	#endif
}