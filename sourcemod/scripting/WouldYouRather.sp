#pragma semicolon 1
#define DEBUG //Uncomment this to enable debug prints to server console.

char chatPrefix[32];

ArrayList alCategories; //Holds the list of categories that filled with questions.

#define questionSize 64
ArrayList alAskingCategories[MAXPLAYERS+1];
ArrayList alAskingQuestions[MAXPLAYERS+1]; //Stores the client's asked question ids, compiled from all the categories.
bool plyParsed[MAXPLAYERS+1];
bool plyShowMainParsed[MAXPLAYERS+1];

//Database stuff:
bool dbLoaded = false;
bool useMySQL = false;
bool cachedPlayers = false;
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
	//cDelete = CreateConVar("sm_wouldyourather_database_deletequestions", "0", "The questions in the database will be deleted and created new from the configs.");
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

public void OnClientPutInServer(int client) {
	createArrayList(alAskingCategories[client]);
	createArrayList(alAskingQuestions[client]);
}

public void OnClientAuthorized(int client, const char[] auth) {
	if(cachedPlayers) {
		loadPlayer(client, null);
	}
}

public void OnClientDisconnect(int client) {
	deleteArrayList(alAskingCategories[client]);
	deleteArrayList(alAskingQuestions[client]);
	plyParsed[client] = false;
	plyShowMainParsed[client] = false;
}

public Action Command_WouldYouRather(int client, int args) {
	if(client <= 0 || !IsClientInGame(client)) {
		ReplyToCommand(client, "You must be ingame to use this command.");
		return Plugin_Handled;
	}
	if(dbLoaded) {
		//Prevent opening the menu if the database isn't even loaded.
		ReplyToCommand(client, "Waiting on database to be loaded.");
		return Plugin_Handled;
	}
	if(!plyParsed[client]) {
		//Not sure if it will ever come to this but we should make sure the player is parsed before showing the menu.
		plyShowMainParsed[client] = true;
		loadPlayer(client, null);
	} else {
		showMainMenu(client);
	}
	return Plugin_Handled;
}


public void showMainMenu(int client) {
	char selection[12];
	char description[72];
	Menu menu = new Menu(mhMain);
	menu.SetTitle("Would You Rather...\n ");
	menu.AddItem("continue", "Continue", alAskingQuestions[client].Length > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("newgame", "New Game");
	menu.AddItem("reset", "Reset Answered Questions");
	menu.Display(client, 0);
}

public int mhMain(Menu menu, MenuAction action, int client, int param2) {
	if(action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "continue")) {
			//Continue with the next question.
			showNextQuestion(client);
		} else if(StrEqual(info, "newgame")) {
			showPlayMenu(client);
		} else {
			//showResetMenu(client);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}
}

public void showPlayMenu(int client) {
	Menu menu = new Menu(mhPlay);
	menu.SetTitle("Would You Rather...\n ");
	menu.AddItem("play", "Play\n \nCategories:", alAskingCategories[client].Length > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	if(alCategories != null && alCategories.Length > 0) {
		char selection[12];
		char description[72];
		char category[32];
		int index = -1;
		for(int c = 0; c < alCategories.Length; c++) {
			alCategories.GetString(c, category, sizeof(category));
			index = alAskingCategories[client].FindValue(c);
			IntToString(c, selection, sizeof(selection));
			Format(description, sizeof(description), "[%s] %s", index != -1 ? "X" : " ", category);
			menu.AddItem(selection, description);
		}
	}
	menu.Display(client, 0);
}

public int mhPlay(Menu menu, MenuAction action, int client, int param2) {
	if(action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "play")) {
			//Start the questions.
			//Add question to player's list.
			/*for(int c = 0; c < MAX_CAT; c++) {
				if(plySelectedCategories[client][c]) {
					for(int i = 0; i < alCatQuestions[c].Length; i++) {
						alAskingQuestions[client].Push(alCatQuestions[c].Get(i));
					}
				}
			}
			if(!nextQuestion(client)) {
				//The player does not have any questions to display.
				showMainMenu(client);
			}*/
		} else {
			int selection = StringToInt(info);
			int index = alAskingCategories[client].FindValue(selection);
			if(index > -1) {
				alAskingCategories[client].Erase(index);
			} else {
				alAskingCategories[client].Push(selection);
			}
			showPlayMenu(client);
		}
	} else if(action == MenuAction_Cancel) {
		showMainMenu(client);
	} else if(action == MenuAction_End) {
		delete menu;
	}
}

/*
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
*/

public int findFromLength(int length) {
	if(cRandom.BoolValue && length > 0) {
		return GetRandomInt(0, length-1);
	}
	return 0;
}

public void getChatPrefix(char[] prefix, int size) {
	if(GetEngineVersion() == Engine_CSGO) {
		Format(prefix, size, " \x08[\x0CWYR\x08]\x01");
	} else {
		Format(prefix, size, "\x07898989[\x07216fedWYR\x07898989]\x01");
	}
}

public void connectToDatabase() {
	dbLoaded = false;
	if(SQL_CheckConfig("wouldyourather")) {
		Database.Connect(dbConnect, "wouldyourather");
	} else {
		SetFailState("Database config for 'wouldyourather' not found. See README for setup guide.");
	}
}

public void dbConnect(Database db, const char[] error, any data) {
	if(db == null) {
		LogMessage("Database failure: %s", error);
	} else {
		dbStats = db;
		DBDriver driver = db.Driver;
		char sDriver[32];
		driver.GetIdentifier(sDriver, sizeof(sDriver));
		useMySQL = StrEqual(sDriver, "mysql", false);
		
		Transaction transaction = new Transaction();
		if(useMySQL) {
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `players` (`accountid` int(32) NOT NULL, `name` varchar(128) NOT NULL, `steam64` varchar(64) NOT NULL, PRIMARY KEY (`accountid`));");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `answers` (`accountid` int(32) NOT NULL, `questionid` int(32) NOT NULL, `answered` int(32) NOT NULL, `time` int(64) DEFAULT 0);");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `selected` (`accountid` int(32) NOT NULL, `category` varchar(32) NOT NULL);");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `questions` (`questionid` int(32) AUTO_INCREMENT, `category` varchar(64) NOT NULL, `question` varchar(64) NOT NULL, `option1` varchar(64) NOT NULL, `option2` varchar(64) NOT NULL, `addedby` int(32) DEFAULT 0, PRIMARY KEY (`questionid`), UNIQUE(`category`, `question`, `option1`, `option2`));");
		} else {
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `players` (`accountid` int(32) NOT NULL, `name` varchar(128) NOT NULL, `steam64` varchar(64) NOT NULL, PRIMARY KEY (`accountid`))");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `answers` (`accountid` int(32) NOT NULL, `questionid` int(32) NOT NULL, `answered` int(32) NOT NULL, `time` int(64) DEFAULT 0)");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `selected` (`accountid` int(32) NOT NULL, `category` varchar(32) NOT NULL)");
			SQL_AddQuery(transaction, "CREATE TABLE IF NOT EXISTS `questions` (`questionid` INTEGER PRIMARY KEY AUTOINCREMENT, `category` varchar(64) PRIMARY KEY NOT NULL, `question` varchar(64) PRIMARY KEY NOT NULL, `option1` varchar(64) PRIMARY KEY PRIMARY KEY NOT NULL, `option2` varchar(64) PRIMARY KEY NOT NULL, PRIMARY KEY (`questionid`, `category`, `question`, `option1`, `option2`));");
		}
		dbStats.Execute(transaction, connectOnSuccess, threadFailure);
	}
}

public void threadFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	LogError("Error in Database Execution: %s", error);
}

public void connectOnSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	dbLoaded = true;
	loadQuestions();
}

public void loadQuestions() {
	if(dbStats == null || !dbLoaded) {
		return;
	}
	char directoryPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, directoryPath, sizeof(directoryPath), "configs/WouldYouRather");
	if(!DirExists(directoryPath)) {
		#if defined DEBUG
		LogMessage("Config folder not found, not injecting questions: %s", directoryPath);
		#endif
	}
	char fullPath[PLATFORM_MAX_PATH];
	char fileName[PLATFORM_MAX_PATH];
	char tempBuffer[(questionSize*3)+2];
	char splitBuffer[3][questionSize];
	char sqlBuffer[512];
	File file;
	FileType fileType;
	int parsedFiles = 0;

	Transaction transaction = new Transaction();
	DirectoryListing directoryListing = OpenDirectory(directoryPath, false);
	while(directoryListing.GetNext(fullPath, sizeof(fullPath), fileType)) {
		if(fileType != FileType_File) {
			continue;
		}

		strcopy(fileName, sizeof(fileName), fullPath);
		Format(fullPath, sizeof(fullPath), "%s/%s", directoryPath, fullPath);
		ReplaceString(fileName, sizeof(fileName), ".cfg", ""); //Strip common file type extensions.
		ReplaceString(fileName, sizeof(fileName), ".txt", "");

		#if defined DEBUG
		PrintToServer("Opening file: %s", fullPath);
		#endif

		file = OpenFile(fullPath, "r");
		while(file.ReadLine(tempBuffer, sizeof(tempBuffer))) {
			TrimString(tempBuffer);
			if(ExplodeString(tempBuffer, "|", splitBuffer, 3, questionSize, false) != 3) {
				//A delimiter was missing or an extra delimiter was found, which means the config might be missing an option, which will screw up the plugin.
				LogError("Config incorrectly configured, delimiter incorrectly defined.");
				LogError("  file: %s", fullPath);
				LogError("  line: %s", tempBuffer);
				SetFailState("Config errors found, please revise the config (see error logs for file and line).");
			}
			if(useMySQL) {
				dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "INSERT IGNORE INTO questions (category, question, option1, option2) VALUES ('%s', '%s', '%s', '%s');", fileName, splitBuffer[0], splitBuffer[1], splitBuffer[2]);
			} else {
				// TODO: test sqlite.
				dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "INSERT OR IGNORE INTO questions (category, question, option1, option2) VALUES ('%s', '%s', '%s', '%s');", fileName, splitBuffer[0], splitBuffer[1], splitBuffer[2]);
			}
			transaction.AddQuery(sqlBuffer);
			parsedFiles++;
		}
		file.Close();
	}
	if(parsedFiles > 0) {
		// Attemp to add the found question configs to the database if the question does not exist.
		dbStats.Execute(transaction, loadQuestionsOnSuccess, threadFailure);
	} else {
		#if defined DEBUG
		PrintToServer("No config files found, no questions or categories will be added to the database.");
		#endif
		delete transaction;
		loadCategories();
	}
}

public void loadQuestionsOnSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	#if defined DEBUG
	PrintToServer("Loaded questions into sql.");
	#endif
	loadCategories();
}

public void loadCategories() {
	if(dbStats == null || !dbLoaded) {
		SetFailState("Unable to load the categories into buffer.");
	}
	if(alCategories == null) {
		alCategories = new ArrayList(ByteCountToCells(32));
	} else {
		alCategories.Clear();
	}
	char sqlBuffer[128];
	if(useMySQL) {
		dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "SELECT DISTINCT `category` FROM questions;");
	} else {
		// TODO: test sqlite.
		dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "SELECT DISTINCT `category` FROM questions;");
	}
	dbStats.Query(loadCategoriesCallback, sqlBuffer);
}

public void loadCategoriesCallback(Database db, DBResultSet results, const char[] error, any data) {
	char tempBuffer[32];
	while(results.FetchRow()) {
		results.FetchString(0, tempBuffer, sizeof(tempBuffer));
		alCategories.PushString(tempBuffer);
		#if defined DEBUG
		PrintToServer("Found category: %s", tempBuffer);
		#endif
	}
	loadAllPlayers();
}

public void loadAllPlayers() {
	Transaction transaction = new Transaction();
	for(int i = 1; i <= MaxClients; i++) {
		loadPlayer(i, transaction);
	}
	dbStats.Execute(transaction, loadAllPlayersSuccess, threadFailure);
}

public void loadPlayer(int client, Transaction trans) {
	if(!dbLoaded || client <= 0 || !IsClientInGame(client)) {
		return;
	}
	Transaction transaction = (trans != null) ? trans : new Transaction();
	char sqlBuffer[256];
	int userId = GetClientUserId(client);
	int accountId = GetSteamAccountID(client);
	// TODO: test this in sqlite.
	dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "SELECT category, questionid FROM questions WHERE category IN (SELECT category FROM selected WHERE accountid = %i) AND questionid NOT IN (SELECT questionid FROM answers WHERE accountid = %i);", accountId, accountId);
	transaction.AddQuery(sqlBuffer, userId);
	if(trans == null) {
		dbStats.Execute(transaction, loadPlayerOnSuccess, threadFailure);
	}
}

public void loadAllPlayersSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	int client;
	for(int x = 0; x < numQueries; x++) {
		client = GetClientOfUserId(queryData[x]);
		if(client <= 0) {
			continue;
		}
		parsePlayer(client, results[x]);
	}
	cachedPlayers = true;
}

public void loadPlayerOnSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	int client = GetClientOfUserId(queryData[0]);
	if(client > 0) {
		parsePlayer(client, results[0]);
	}
}

public void parsePlayer(int client, DBResultSet result) {
	if(result.RowCount > 0) {
		char tempBuffer[32];
		int index;
		int category;
		while(result.FetchRow()) {
			result.FetchString(0, tempBuffer, sizeof(tempBuffer));
			//Find the category in the category list
			category = alCategories.FindString(tempBuffer);
			if(category != -1) {
				//Add the selected category to the player's list, if it does not already exist.
				index = alAskingCategories[client].FindValue(category);
				if(index == -1) {
					alAskingCategories[client].Push(index);
				}
			}
			alAskingQuestions[client].Push(result.FetchInt(1));
		}
	}
	plyParsed[client] = true;
	if(plyShowMainParsed[client]) {
		showMainMenu(client);
	}
}

public void createArrayList(ArrayList &array) {
	if(array == null) {
		array = new ArrayList();
	} else {
		array.Clear();
	}
}

public void deleteArrayList(ArrayList &array) {
	if(array != null) {
		delete array;
		array = null;
	}
}