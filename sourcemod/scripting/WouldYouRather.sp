#pragma semicolon 1
//#define DEBUG //Uncomment this to enable debug prints to server console.

char chatPrefix[32];

#define MAX_CAT 8 //8 Categories max because there are 8 slots usable in the panel atleast for csgo.
char catName[MAX_CAT][32];
ArrayList alCatQuestions[MAX_CAT]; //This stores all the indices to the question, and the two options in the ArrayList below.

//Compiles all the indices that point to the actual questions, when a client answers it then we just erase the answered question from this list.
ArrayList alAskingQuestions[MAXPLAYERS+1]; 	
											
bool plySelectedCategories[MAXPLAYERS+1][MAX_CAT]; //Temporarily stores if the player has selected this category.

#define questionSize 64
#define QUESTION 0
#define OPTIONA  1
#define OPTIONB  2
ArrayList alQuestions[3];

//Database stuff:
bool dbiLoaded = false;
bool useDBI = false;
bool useMySQL = false;
Database dbStats;

ConVar cRandom;
ConVar cSpacer;

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
	cRandom = CreateConVar("sm_wouldyourather_random", "1", "Randomize the order of the questions before showing the client.");
	cSpacer = CreateConVar("sm_wouldyourather_menuspacer", "1", "0 For no menu spacer when being asked questions, 1 For menu spacers and the text 'Or...'");
	AutoExecConfig(true, "WouldYouRather");

	RegConsoleCmd("sm_wyr", Command_WouldYouRather);
	RegConsoleCmd("sm_wouldyourather", Command_WouldYouRather);

	connectToDatabase();
	
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public OnMapStart() {
	reloadConfig();
}

public void OnClientPutInServer(int client) {
	if(alAskingQuestions[client] == null) {
		alAskingQuestions[client] = new ArrayList();
	} else {
		alAskingQuestions[client].Clear();
	}
	for(int c = 0; c < MAX_CAT; c++) {
		plySelectedCategories[client][c] = false;
	}
}

public void OnClientDisconnect(int client) {
	if(alAskingQuestions[client] != null) {
		delete alAskingQuestions[client];
		alAskingQuestions[client] = null;
	}
}

public Action Command_WouldYouRather(int client, int args) {
	if(client <= 0 || !IsClientInGame(client)) {
		ReplyToCommand(client, "You must be iname to use this command.");
		return Plugin_Handled;
	}
	showMainMenu(client);
	return Plugin_Handled;
}

public void showMainMenu(int client) {
	char selection[12];
	char description[72];
	Menu menu = new Menu(mhMain);
	menu.SetTitle("Would You Rather...\n ");
	bool hasSelected = false;
	for(int c = 0; c < MAX_CAT; c++) {
		if((hasSelected = plySelectedCategories[client][c])) {
			break;
		}
	}
	bool hasAlreadyStarted = alAskingQuestions[client].Length > 0;
	menu.AddItem("continue", "Continue", hasAlreadyStarted ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("play", "New Game\n \nCategories:", hasSelected ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	for(int c = 0; c < MAX_CAT; c++) {
		if(alCatQuestions[c] == null || alCatQuestions[c].Length <= 0) {
			//Either no questions inputted or doesn't exist.
			break;
		}
		IntToString(c, selection, sizeof(selection));
		Format(description, sizeof(description), "[%s] %s", plySelectedCategories[client][c] ? "X" : " ", catName[c]);
		menu.AddItem(selection, description);
	}
	menu.Display(client, 0);
}

public int mhMain(Menu menu, MenuAction action, int client, int param2) {
	if(action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "play")) {
			//Start the questions.
			//Add question to player's list.
			for(int c = 0; c < MAX_CAT; c++) {
				if(plySelectedCategories[client][c]) {
					for(int i = 0; i < alCatQuestions[c].Length; i++) {
						alAskingQuestions[client].Push(alCatQuestions[c].Get(i));
					}
				}
			}
			if(!nextQuestion(client)) {
				//The player does not have any questions to display.
				showMainMenu(client);
			}
		} else if(StrEqual(info, "continue")) {
			//Continue with the next question.
			if(!nextQuestion(client)) {
				showMainMenu(client); //Show the main menu if there is no next question..
			}
		} else {
			int selection = StringToInt(info);
			plySelectedCategories[client][selection] = !plySelectedCategories[client][selection];
			showMainMenu(client);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}
}

public void showQuestionMenu(int client, int question) {
	char selection[32];
	char optionBuffer[64];

	Menu menu = new Menu(mhOption);
	alQuestions[QUESTION].GetString(question, optionBuffer, sizeof(optionBuffer));
	menu.SetTitle("%s\n ", optionBuffer);

	Format(selection, sizeof(selection), "!%i", question);
	alQuestions[OPTIONA].GetString(question, optionBuffer, sizeof(optionBuffer));
	if(cSpacer.BoolValue) {
		Format(optionBuffer, sizeof(optionBuffer), "%s\nOr...", optionBuffer);
	}
	menu.AddItem(selection, optionBuffer);

	IntToString(question, selection, sizeof(selection));
	alQuestions[OPTIONB].GetString(question, optionBuffer, sizeof(optionBuffer));
	menu.AddItem(selection, optionBuffer);

	menu.Pagination = false;
	menu.ExitButton = true;
	menu.Display(client, 0);
}

public int mhOption(Menu menu, MenuAction action, int client, int param2) {
	if(action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		//int selection = (StrContains(info, "!") == 0) ? 1 : 2; //Maybe used later on to show stats of this question.
		ReplaceString(info, sizeof(info), "!", "");
		int question = StringToInt(info);
		int index = alAskingQuestions[client].FindValue(question);
		if(index != -1) {
			//Question was answered, remove it from the personal list.
			alAskingQuestions[client].Erase(index);
		}
		if(!nextQuestion(client)) {
			PrintToChat(client, "%s Finished all questions in your collection.", chatPrefix);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

public bool nextQuestion(int client) {
	int length = alAskingQuestions[client].Length;
	if(length <= 0) {
		return false;
	}
	int questionIndex = alAskingQuestions[client].Get(findFromLength(length));
	showQuestionMenu(client, questionIndex);
	return true;
}

public int findFromLength(int length) {
	if(cRandom.BoolValue && length > 0) {
		return GetRandomInt(0, length-1);
	}
	return 0;
}

public void reloadConfig() {
	int bufferSize = ByteCountToCells(questionSize);
	for(int i = 0; i < 3; i++ ) {
		if(alQuestions[i] != null) {
			alQuestions[i].Clear();
		} else {
			alQuestions[i] = new ArrayList(bufferSize);
		}
	}
	for(int c = 0; c < MAX_CAT; c++ ) {
		if(alCatQuestions[c] != null) {
			delete alCatQuestions[c];
			alCatQuestions[c] = null;
		}
	}
	int confCategory = 0;

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

	DirectoryListing directoryListing = OpenDirectory(directoryPath, false);
	while(directoryListing.GetNext(fullPath, sizeof(fullPath), fileType)) {
		if(fileType != FileType_File) {
			continue;
		}
		if(confCategory >= MAX_CAT) {
			LogError("Hit the max category limit of %i categories, ignoring the rest.", MAX_CAT);
			break;
		}
		strcopy(fileName, sizeof(fileName), fullPath);
		Format(fullPath, sizeof(fullPath), "%s/%s", directoryPath, fullPath);
		ReplaceString(fileName, sizeof(fileName), ".cfg", "");
		ReplaceString(fileName, sizeof(fileName), ".txt", "");
		strcopy(catName[confCategory], sizeof(catName[]), fileName); //Save the file name as the name of the category.
		alCatQuestions[confCategory] = new ArrayList(); // Create a reference to the next questions.
		
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

			int quickIndex = -1;
			for(int q = 0; q < 3; q++) {
				quickIndex = alQuestions[q].PushString(splitBuffer[q]);
			}

			alCatQuestions[confCategory].Push(quickIndex);
		}
		file.Close();
		confCategory++;
	}
	if(confCategory == 0) {
		LogError("No categories were found or loaded, please check your config.");
	}
	#if defined DEBUG
	PrintToServer("Found %i categories", confCategory);
	PrintToServer("------------------------");
	int index;
	for(int c = 0; c < confCategory; c++) {
		PrintToServer("Displaying category %i", c+1);
		for(int i = 0; i < alCatQuestions[c].Length; i++) {
			index = alCatQuestions[c].Get(i);
			for(int q = 0; q < 3; q++) {
				alQuestions[q].GetString(index, splitBuffer[q], sizeof(splitBuffer[]));
			}
			PrintToServer("%s:%s:%s", splitBuffer[0], splitBuffer[1], splitBuffer[2]);
		}
		PrintToServer("------------------------");
	}
	#endif
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
	Database.Connect(dbConnect, "wouldyourather");
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
		driver.GetIdentirifier(sDriver, sizeof(sDriver));
		useMySQL = StrEqual(sDriver, "mysql", false);
		
		Transaction transaction = new Transaction();
		if(useMySQL) {
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `players` (`accountid` int(32) NOT NULL, `name` varchar(128) NOT NULL, `steam64` varchar(64) NOT NULL, PRIMARY KEY (`accountid`));");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `answers` (`accountid` int(32) NOT NULL, `questionid` int(32) NOT NULL, `answered` int(32) NOT NULL, `time` int(64) DEFAULT 0);");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `questions` (`questionid` int(32) AUTO_INCREMENT, `category` varchar(64) NOT NULL, `description` varchar(128), `question` varchar(64) NOT NULL, `option1` varchar(64) NOT NULL, `option2` varchar(64) NOT NULL, PRIMARY KEY (`id`));");
		} else {
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `players` (`accountid` int(32) NOT NULL, `name` varchar(128) NOT NULL, `steam64` varchar(64) NOT NULL, PRIMARY KEY (`accountid`))");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `answers` (`accountid` int(32) NOT NULL, `questionid` int(32) NOT NULL, `answered` int(32) NOT NULL, `time` int(64) DEFAULT 0)");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `questions` (`questionid` INTEGER PRIMARY KEY AUTOINCREMENT, `category` varchar(64) NOT NULL, `description` varchar(128), `question` varchar(64) NOT NULL, `option1` varchar(64) NOT NULL, `option2` varchar(64) NOT NULL);");
		}
		dbStats.Execute(transaction, connectOnSuccess, connectFailure);
	}
}

public void connectOnSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	dbiLoaded = true;
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
	dbStats.Format("SELECT name FROM players WHERE accountid='%i'", accountId);
	//The player should only exist in the database if they have played the game before, otherwise why store their information?
	if(trans == null) {
		dbStats.Execute(transaction, loadPlayerOnSuccess, threadFailure);
	}
}

public void loadPlayerOnSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	int client;
	char clientName[128];
	for(int x = 0; x < numQueries; x++) {
		client = GetClientOfUserId(queryData[x])
		if(client <= 0) {
			continue;
		}
		if(results[x].RowCount > 0) {
			char tempName[128];
			while(results[x].FetchRow()) {
				results.FetchString(0, tempName, sizeof(tempName));
			}
			GetClientName(client, clientName);
			if(!StrEqual(clientName, tempName)) {
				//If the player already exists then update their name.
				updatePlayerName(client, clientName);
			}
		}
	}
}


