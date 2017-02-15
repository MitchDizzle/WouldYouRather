#pragma semicolon 1

#define MAX_CAT 8 //8 Categories max because there are 8 slots usable in the panel atleast for csgo.
char catName[MAX_CAT][32];
char catDescription[MAX_CAT][128];
ArrayList alCatQuestions[MAX_CAT]; //This stores all the indices to the question, and the two options in the ArrayList below.

#define questionSize 64
#define QUESTION 0
#define OPTIONA  1
#define OPTIONB  2
ArrayList alQuestions[3];

EngineVersion engineVersion;

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "Would You Rather..",
	author = "Mitch",
	description = "A simple would you rather game.",
	version = PLUGIN_VERSION,
	url = "http://mtch.tech"
};

public OnPluginStart() {
	
	engineVersion = GetEngineVersion();
}

public OnMapStart() {
	reloadConfig();
}

public bool reloadConfig() {
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
	bool confDescription;

	char directoryPath[PLATFORM_MAX_PATH];
	char fullPath[PLATFORM_MAX_PATH];
	char fileName[PLATFORM_MAX_PATH];
	char tempBuffer[(questionSize*3)+2];
	char splitBuffer[3][questionSize];
	int count;
	File file;
	FileType fileType;

	BuildPath(Path_SM, directoryPath, sizeof(directoryPath), "configs/WouldYouRather/");
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
		ReplaceString(fileName, sizeof(fileName), ".cfg", "");
		strcopy(catName[confCategory], sizeof(catName[]), fileName); //Save the file name as the name of the category.
		alCatQuestions[confCategory] = new ArrayList(bufferSize); // Create a reference to the next questions.
		confDescription = true;
		Format(fullPath, sizeof(fullPath), "%s%s", directoryPath, fullPath);
		PrintToServer("Opening File: %s", fullPath);
		file = OpenFile(fullPath, "r");
		while(file.ReadLine(tempBuffer, sizeof(tempBuffer))) {
			TrimString(tempBuffer);
			if(confDescription) {
				strcopy(catDescription[confCategory], sizeof(catDescription[]), tempBuffer); //Save the category's description.
				confDescription = false;
				continue;
			}

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
		confCategory++;
	}
	
	PrintToServer("Found %i categories", confCategory);
	int index;
	PrintToServer("------------------------");
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
}