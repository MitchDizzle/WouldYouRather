# WouldYouRather [Source 2013/CS:GO]

A List of changes between versions
  
## 1.1

* Database (MySQL/SQLite) support.
* Full rewrite on how the questions are stored.
* Now stores config into database for 'easy' sql lookup.
* Category names are cached within a ArrayList.
* Player have their own 2 ArrayLists which store their unanswered question ids and selected categories.
* When player connects, it will now store their previous categories and unanswered questions.
* New main menu which shows Continue, New Game, and Reset.
* New play menu which shows the categories and play. Pressing play will reset selected categories incase of reconnect.
* When a player starts a new game it will find unanswered questions for the selected categories.
* When a player answers a question store that answers
  * Retrieve the next question from their list.

Unfinished:

* New reset menu which will allow players to reset their answers for specific categories.

## 1.0

* Initial Release
* Loading categories from config
* Displaying menu
  * Menu shows toggable categories
  * Menu will show questions from all selected categories until finished.
  * Menu will continue progress if exited prematurely.
