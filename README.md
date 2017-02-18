# WouldYouRather [Source 2013/CS:GO]

A Simple would you rather game that shows in the in game radio menu. Currently there is no tracking of stats, so if a player leaves the server he/she may be answering questions that he has already seen in a previous session. If a client closes the menu then they will have the chance to restart their questions from the beginning, or continue where they left off, if a player restarts they may see questions that were already shown.

## Config

The config for the questions is setup to be as simple as adding lines to a file or adding an additional file for a new category.

To add a new category just start an empty file within the `sourcemod/configs/WouldYouRather`. The name of the file is the name of the category.

To add questions and options to your category just follow the format of

`QUESTION|OPTION1|OPTION2`

The delimiter is the '|' character. If you do not have two of the delimiter characters the plugin will unload and tell you what line it is on.

## Contributing

To contribute to the plugin or it's questions please see the [contribution guidelines](CONTRIBUTING.md)

## Version Change Log

Please view the corresponding [changelog](CHANGES.md)

## Future Plans

I'm planning on adding a webserver (preferably java) that will communicate through Http requests. This will allow the webserver to hold the stats per player, instead of having the server save all the stats. If I do actually get around to finishing the webserver then it would be in a different destination, as I want to keep them separate.
