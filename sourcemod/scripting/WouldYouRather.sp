#pragma semicolon 1
#define DEBUG //Uncomment this to enable debug prints to server console.

char chatPrefix[32];

ArrayList alCategories; //Holds the list of categories that filled with questions.

#define questionSize 64
ArrayList alAskingCategories[MAXPLAYERS+1];
ArrayList alAskingQuestions[MAXPLAYERS+1]; //Stores the client's asked question ids, compiled from all the categories.
bool plyParsed[MAXPLAYERS+1];
bool plyShowMainParsed[MAXPLAYERS+1];
bool plyShowQuestionParse[MAXPLAYERS+1];

//Database stuff:
bool dbLoaded = false;
bool useMySQL = false;
bool cachedPlayers = false;
Database dbStats;

ConVar cRandom;
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
	cRandom = CreateConVar("sm_wouldyourather_random", "1", "Randomize the order of the questions before showing the client.");
	//cSpacer = CreateConVar("sm_wouldyourather_menuspacer", "1", "0 For no menu spacer when being asked questions, 1 For menu spacers and the text 'Or...'");
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
	if(!dbLoaded) {
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
	Menu menu = new Menu(mhMain);
	char description[128];
	menu.SetTitle("Would You Rather...\n ");
	int unansweredQuestions = alAskingQuestions[client].Length;
	Format(description, sizeof(description), "Continue");
	if(unansweredQuestions > 0) {
		Format(description, sizeof(description), "%s (%i)", description, unansweredQuestions);
	}
	menu.AddItem("continue", description, unansweredQuestions > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
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
			int nextQuestion = findNextQuestion(client);
			if(nextQuestion != -1) {
				requestQuestion(client, nextQuestion, null);
			}
		} else if(StrEqual(info, "newgame")) {
			showNewGameMenu(client);
		} else {
			showResetMenu(client);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}
}

public void generateCategoryItems(Menu menu,int client) {
	if(alCategories != null && alCategories.Length > 0) {
		char selection[12];
		char description[72];
		char category[32];
		int index;
		for(int c = 0; c < alCategories.Length; c++) {
			alCategories.GetString(c, category, sizeof(category));
			index = alAskingCategories[client].FindValue(c);
			IntToString(c, selection, sizeof(selection));
			Format(description, sizeof(description), "[%s] %s", index != -1 ? "X" : " ", category);
			menu.AddItem(selection, description);
		}
	}
}

public void handleCategorySelection(int client, int selection) {
	int index = alAskingCategories[client].FindValue(selection);
	if(index > -1) {
		alAskingCategories[client].Erase(index);
	} else {
		alAskingCategories[client].Push(selection);
	}
}

public void showNewGameMenu(int client) {
	Menu menu = new Menu(mhNewGame);
	menu.SetTitle("Would You Rather...\n ");
	menu.AddItem("play", "Play\n \nCategories:", alAskingCategories[client].Length > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	generateCategoryItems(menu, client);
	menu.Display(client, 0);
}

public int mhNewGame(Menu menu, MenuAction action, int client, int param2) {
	if(action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "play")) {
			newGame(client);
		} else {
			int selection = StringToInt(info);
			handleCategorySelection(client, selection);
			showNewGameMenu(client);
		}
	} else if(action == MenuAction_Cancel) {
		showMainMenu(client);
	} else if(action == MenuAction_End) {
		delete menu;
	}
}

public void showResetMenu(int client) {
	Menu menu = new Menu(mhReset);
	menu.SetTitle("Reset Answered Questions\n ");
	menu.AddItem("reset", "Reset\n \nCategories:", alAskingCategories[client].Length > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	generateCategoryItems(menu, client);
	menu.AddItem("spacer", "spacer", ITEMDRAW_SPACER);
	menu.AddItem("resetall", "Reset All Categories");
	menu.Display(client, 0);
}

public int mhReset(Menu menu, MenuAction action, int client, int param2) {
	if(action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "reset")) {
			resetSelectedCategories(client, false);
		} else if(StrEqual(info, "resetall")) {
			resetSelectedCategories(client, true);
		} else {
			int selection = StringToInt(info);
			handleCategorySelection(client, selection);
			showResetMenu(client);
		}
	} else if(action == MenuAction_Cancel) {
		showMainMenu(client);
	} else if(action == MenuAction_End) {
		delete menu;
	}
}

public void resetSelectedCategories(int client, bool all) {
	if(alCategories != null && alCategories.Length > 0) {
		int accountId = GetSteamAccountID(client);
		char category[32];
		char sqlBuffer[256];
		int categoryId;
		//Erase only the selected categories.
		Transaction transaction = new Transaction();
		int size = all ? alCategories.Length : alAskingCategories[client].Length;
		for(int c = 0; c < size; c++) {
			categoryId = alAskingCategories[client].Get(c);
			alCategories.GetString(categoryId, category, sizeof(category));
			dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "DELETE FROM answers WHERE accountid='%i' AND questionid IN (SELECT questionid FROM questions WHERE category='%s');", accountId, category);
			transaction.AddQuery(sqlBuffer, categoryId);
		}
		dbStats.Execute(transaction, resetCategoryTransactionCallback, threadFailure, GetClientUserId(client));
	} else {
		PrintToChat(client, "%s No categories selected.", chatPrefix); //This shouldn't happen.
	}
}

public void resetCategoryTransactionCallback(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	int client = GetClientOfUserId(data);
	if(client <= 0) {
		return;
	}
	char categoryFormat[255];
	char category[255];
	int categoryId;
	int categoryCount;
	for(int x = 0; x < numQueries; x++) {
		categoryId = queryData[x];
		alCategories.GetString(categoryId, category, sizeof(category));
		if(categoryCount == 0) {
			Format(categoryFormat, sizeof(categoryFormat), "%s", category);
		} else if(categoryCount < 3) {
			Format(categoryFormat, sizeof(categoryFormat), "%s%s%s", categoryFormat, (numQueries == 2) ? " and " : ", ", category);
		}
		categoryCount++;
	}
	if(categoryCount >= 3) {
		Format(categoryFormat, sizeof(categoryFormat), "%s and %i other", categoryFormat, categoryCount-3);
	}
	PrintToChat(client, "%s %s answered categories reset.", chatPrefix, categoryFormat);
}

int plyShowingQuestion[MAXPLAYERS+1];
public void requestQuestion(int client, int questionId, Transaction transaction) {
	if(questionId < 0) {
		return;
	}
	plyShowingQuestion[client] = questionId;
	char sqlBuffer[256];
	dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "SELECT category, question, option1, option2 FROM questions WHERE questionid='%i'", questionId);
	if(transaction != null) {
		transaction.AddQuery(sqlBuffer);
	} else {
		dbStats.Query(showQuestionCallback, sqlBuffer, GetClientUserId(client));
	}
}

public sendAnswer(int client, int answer) {
	int index = alAskingQuestions[client].FindValue(plyShowingQuestion[client]);
	if(index != -1) {
		alAskingQuestions[client].Erase(index);
	}

	Transaction transaction = new Transaction();
	
	char sqlBuffer[256];
	int accountId = GetSteamAccountID(client);
	dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "%s INTO answers (accountid, questionid, answered, time) VALUES ('%i', '%i', '%i', '%i');", useMySQL ? "REPLACE" : "INSERT OR REPLACE", accountId, plyShowingQuestion[client], answer, GetTime());
	transaction.AddQuery(sqlBuffer);
	
	int nextQuestion = findNextQuestion(client);
	if(nextQuestion != -1) {
		requestQuestion(client, nextQuestion, transaction);
	} else {
		PrintToChat(client, "%s All questions answered.", chatPrefix);
	}
	dbStats.Execute(transaction, showQuestionTransactionCallback, threadFailure, GetClientUserId(client));
}

public void showQuestionTransactionCallback(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	int client = GetClientOfUserId(data);
	if(client <= 0) {
		return;
	}
	for(int x = 0; x < numQueries; x++) {
		if(results[x].HasResults) {
			parseQuestion(client, results[x]);
		}
	}
}

public void showQuestionCallback(Database db, DBResultSet results, const char[] error, any data) {
	int client = GetClientOfUserId(data);
	if(client <= 0) {
		return;
	}
	parseQuestion(client, results);
}

public void parseQuestion(int client, DBResultSet result) {
	char category[32];
	char question[3][64];
	if(result.RowCount > 0) {
		while(result.FetchRow()) {
			result.FetchString(0, category, sizeof(category));
			result.FetchString(1, question[0], sizeof(question[]));
			result.FetchString(2, question[1], sizeof(question[]));
			result.FetchString(3, question[2], sizeof(question[]));
		}
		//Incase of multiple results send only one menu with the last result. (Impossible!)
		showQuestion(client, category, question);
	}
}

public void showQuestion(int client, char[] category, char[][] question) {
	Menu menu = new Menu(mhOption);
	menu.SetTitle("%s: (%i)\n%s\n ", category, alAskingQuestions[client].Length, question[0]);
	menu.AddItem("1", question[1]);
	menu.AddItem("2", question[2]);
	menu.Pagination = false;
	menu.ExitButton = true;
	menu.Display(client, 0);
}

public int mhOption(Menu menu, MenuAction action, int client, int param2) {
	if(action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		sendAnswer(client, StringToInt(info));
	} else if(action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

public int findNextQuestion(int client) {
	int length = alAskingQuestions[client].Length;
	if(length <= 0) {
		return -1;
	}
	return alAskingQuestions[client].Get(findFromLength(length));
}

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
			transaction.AddQuery("CREATE TABLE IF NOT EXISTS `players` (`accountid` int(32) NOT NULL, `name` varchar(128) NOT NULL, `steam64` varchar(64) NOT NULL, PRIMARY KEY (`accountid`));");
			transaction.AddQuery("CREATE TABLE IF NOT EXISTS `answers` (`accountid` int(32) NOT NULL, `questionid` int(32) NOT NULL, `answered` int(32) NOT NULL, `time` int(64) DEFAULT 0, UNIQUE(`accountid`, `questionid`));");
			transaction.AddQuery("CREATE TABLE IF NOT EXISTS `selected` (`accountid` int(32) NOT NULL, `category` varchar(32) NOT NULL, UNIQUE(`accountid`, `category`));");
			transaction.AddQuery("CREATE TABLE IF NOT EXISTS `questions` (`questionid` int(32) AUTO_INCREMENT, `category` varchar(64) NOT NULL, `question` varchar(64) NOT NULL, `option1` varchar(64) NOT NULL, `option2` varchar(64) NOT NULL, `addedby` int(32) DEFAULT 0, PRIMARY KEY (`questionid`), UNIQUE(`category`, `question`, `option1`, `option2`));");
		} else {
			transaction.AddQuery("CREATE TABLE IF NOT EXISTS `players` (`accountid` int(32) PRIMARY KEY NOT NULL, `name` varchar(128) NOT NULL, `steam64` varchar(64) NOT NULL);");
			transaction.AddQuery("CREATE TABLE IF NOT EXISTS `answers` (`accountid` int(32) NOT NULL, `questionid` int(32) NOT NULL, `answered` int(32) NOT NULL, `time` int(64) DEFAULT 0, UNIQUE(`accountid`, `questionid`) ON CONFLICT IGNORE);");
			transaction.AddQuery("CREATE TABLE IF NOT EXISTS `selected` (`accountid` int(32) NOT NULL, `category` varchar(32) NOT NULL, UNIQUE(`accountid`, `category`) ON CONFLICT IGNORE);");
			transaction.AddQuery("CREATE TABLE IF NOT EXISTS `questions` (`questionid` INTEGER PRIMARY KEY AUTOINCREMENT, `category` varchar(64) NOT NULL, `question` varchar(64) NOT NULL, `option1` varchar(64) NOT NULL, `option2` varchar(64) NOT NULL, UNIQUE(`category`, `question`, `option1`, `option2`) ON CONFLICT IGNORE);");
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
			dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "INSERT %s IGNORE INTO questions (category, question, option1, option2) VALUES ('%s', '%s', '%s', '%s');", useMySQL ? "" : "OR", fileName, splitBuffer[0], splitBuffer[1], splitBuffer[2]);
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
	dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "SELECT DISTINCT `category` FROM questions;");
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
	int accountId = GetSteamAccountID(client);
	// TODO: test this in sqlite.
	dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "SELECT category, questionid FROM questions WHERE category IN (SELECT category FROM selected WHERE accountid = %i) AND questionid NOT IN (SELECT questionid FROM answers WHERE accountid = %i);", accountId, accountId);
	transaction.AddQuery(sqlBuffer, GetClientUserId(client));
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
		createArrayList(alAskingCategories[client]);
		createArrayList(alAskingQuestions[client]);
		while(result.FetchRow()) {
			result.FetchString(0, tempBuffer, sizeof(tempBuffer));
			//Find the category in the category list
			category = alCategories.FindString(tempBuffer);
			if(category != -1) {
				//Add the selected category to the player's list, if it does not already exist.
				index = alAskingCategories[client].FindValue(category);
				if(index == -1) {
					alAskingCategories[client].Push(category);
				}
			}
			int tempInt = result.FetchInt(1);
			#if defined DEBUG
			PrintToServer("%N - %s = %i", client, tempBuffer, tempInt);
			#endif
			alAskingQuestions[client].Push(tempInt);
		}
	}
	plyParsed[client] = true;
	if(plyShowMainParsed[client]) {
		plyShowMainParsed[client] = false;
		showMainMenu(client);
	}
	if(plyShowQuestionParse[client]) {
		plyShowQuestionParse[client] = false;
		int nextQuestion = findNextQuestion(client);
		if(nextQuestion != -1) {
			requestQuestion(client, nextQuestion, null);
		} else {
			PrintToChat(client, "%s No unanswered questions found for the selected categories.", chatPrefix);
		}
	}
}

//Delete old categories saved under the player's list. X
//Send new categories for the player's list. X
//Retrieve player's questions. X
public void newGame(int client) {
	createArrayList(alAskingQuestions[client]);
	int accountId = GetSteamAccountID(client);
	char clientName[128];
	GetClientName(client, clientName, sizeof(clientName));
	char steam64[64];
	GetClientAuthId(client, AuthId_SteamID64, steam64, sizeof(steam64));
	char sqlBuffer[128];
	Transaction transaction = new Transaction();
	//Delete old categories, this is easier than storing storing the data in the plugin and finding the difference.
	dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "DELETE FROM selected WHERE accountid='%i'", accountId);
	transaction.AddQuery(sqlBuffer, 0);
	
	//TODO: Safe guard against "STEAM_ID_STOP_IGNORING_RETVALS"
	dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "%s INTO players (accountid, name, steam64) VALUES ('%i', '%s', '%s');", useMySQL ? "REPLACE" : "INSERT OR REPLACE", accountId, clientName, steam64);
	transaction.AddQuery(sqlBuffer, 0);
	
	int cat;
	char category[32];
	for(int c = 0; c < alAskingCategories[client].Length; c++) {
		cat = alAskingCategories[client].Get(c);
		if(cat != -1) {
			alCategories.GetString(cat, category, sizeof(category));
			dbStats.Format(sqlBuffer, sizeof(sqlBuffer), "INSERT %s IGNORE INTO selected (accountid, category) VALUES ('%i', '%s');", useMySQL ? "" : "OR", accountId, category);
			transaction.AddQuery(sqlBuffer, 0);
		}
	}
	//Attempt to get the unanswered questions in the same transaction, saving time.
	loadPlayer(client, transaction); 
	dbStats.Execute(transaction, newGameOnSuccess, threadFailure);
}

public void newGameOnSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	int client;
	for(int x = 0; x < numQueries; x++) {
		if(queryData[x] <= 0) {
			continue;
		}
		client = GetClientOfUserId(queryData[x]);
		if(client <= 0) {
			continue;
		}
		plyShowQuestionParse[client] = true;
		parsePlayer(client, results[x]);
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