# Task 004 - User Interface and Saves

## Goal

Implement a main menu, world selector, and pause menu for the Wildes game. We will need to implement a world save system that allows the user to save up to three worlds. 

## Requirements

### User Interface and Design
The UI design of Wildes will use a blur/frosted effect on **ALL** UI elements, similar to the macOS / Windows 11 UI blur/frosted effect. 

There will be two main types of UI elements, modals and buttons, and this is the design schema that I landed on:

1. Modals
    - Background Color: `Color(0.14, 0.16, 0.18, 0.32)`
    - Border Radius: `18 all`
    - Border: `1 all`
    - Border Color: `Color(1, 1, 1, 0.20)`
    - Material: Frosted/Blur 
    - Font Family: Roboto Slab

2. Buttons
    - Background Color: `Color(0.20, 0.22, 0.24, 0.38)` with additional `src.a 0.38 = 62% blur + 38% dark tint`
    - Border Radius: `14 all`
    - Border: `1 all`
    - Border Color: `Color(1, 1, 1, 0.20)`
    - Material: Frosted/Blur
    - Font Family: Roboto Slab

We will need to develop our own shader material for the blur effect to work correctly. 

#### Main Menu
Once we have the modals and buttons design in place, we need to implement the main menu of this game which is a simple title screen with a play button. Below is a diagram of the main menu:
```
|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾| 
|                          |
|                          |
|   Wildes        [Play]   | 
|                          | 
|                          |
|__________________________|
```
We should have the title screen on the left side and a medium sized play button on the right side. Both are centered. The color for the background is a deep navy color with off white text color.

#### World Select modal
When the user clicks on the 'Play' button, we should pop open another menu screen that allows the user to select their world. Below is a diagram of what I am looking for:
```
|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾| 
|       SELECT WORLD       |
|   |‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|  |
|   |   Empty Slot 1    |  |
|   |___________________|  |
|   |‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|  |
|   |   Empty Slot 2    |  |
|   |___________________|  |
|   |‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|  |
|   |   Empty Slot 3    |  |  
|   |___________________|  |
|__________________________|
```

When a world is saved we should display the world name, the seed used for world generation, and the last time the user played on the world. All text is center aligned. We also have a button on the bottom right that says "Delete" if a world is saved. 

#### Delete World modal
When the user clicks on the Delete button the following modal pops up:
```
|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾| 
|       Delete World?      |
|        World Name        | 
|   <Modal Description>    |
|                          |
|   [<Button>]  [Cancel]   |
|__________________________|
```
The placeholders in the diagram contain this text:
1. `<Modal Description>`: Hold the button down for 3 seconds to permanently delete this world. This cannot be undone.
2. `<Button>`: HOLD TO DELETE

The user needs to hold the button down for three seconds, when held down, the space inbetween the modal description and the button group should show a progress bar that progressively fills up when the button is being held, the "HOLD TO DELETE" button should show "HOLDING... X.X/3s" where X.X is the number of seconds the button is being held for in that current instance. 

#### Create World modal
When a user selects a blank slot, we overlay a Create World modal and dim the background. Below is a diagram of the modal design:

```
|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾| 
|     Create New World     |
|   ____________________   | 
|   _________[Randomize]   |
|                          |
|   [Cancel]    [Create]   |
|__________________________|
```
The modal has two text fields, shows as "__..._" in the diagram, where the first one is the world name text field and the second is the seed text field. Next to the seed text field is a button that says "Randomize" where a random seed can be generated. 

We also have Cancel and Create buttons where cancel removes the modal popup and shows the World Select modal again. When a user creates the world, we start generating the world for the user.

#### World Generation Screen
After a user clicks on "Create" inside of the Create World modal, we remove all UI elements and show this modal:
```
|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾| 
|          WILDES          |
|                          | 
|  Loading World           | 
|  ████████⎕⎕⎕⎕⎕⎕⎕⎕⎕⎕⎕⎕⎕⎕  | 
|  Chunks: Chunks X/Y      | 
|__________________________|
```
We show the title of the game in a large font, Loading World in medium font, a progress bar which keeps track of the progress of the chunks being loaded and we also show a subtitle, small font, of the total chunks loaded.

#### Pause modal
When a user is in the playable game state and the user pressed `esc` on the keyboard, we need to show a paused modal as shown below:
```
|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾| 
|          PAUSED          |
|                          | 
|         [RESUME]         | 
|        [MAIN MENU]       | 
|__________________________|
```
Pressing resume just removes the modal while "MAIN MENU", saves, closes the world, and brings the user back to the Main Menu

While the game is in a pause modal, the game is in a paused state and **ALL** game states and timers are frozen. 

### World Saves

You will need to implement local saves in this task so that the World Select modal works properly. When a world is saved, we need to save EVERYTHING in the current game which includes:

1. World
2. Character Position
3. Placed / Broken Blocks
4. Timers
5. World Time

## Technical Requirements
- Godot 4.7
- One external Apache License V2 font asset will need to be imported: Roboto Slab

## Acceptance Criteria
- The game is able to run headless
- The following UI flows work properly:
    1. Main Menu -> Play -> Select empty slot 1 -> Input World name -> Input seed -> Create World -> Pause Game -> Main menu
    2. Main Menu -> Play -> Select World Slot 1 -> Pause -> Resume -> Pause -> Main Menu -> Play -> Select Empty Slot 2 -> Input World name -> Input seed -> Create World -> Pause Game -> Main menu
    3. Main Menu -> Play -> Select World Slot 1 -> Pause -> Main Menu -> Play -> Select World Slot 2 -> Pause -> Main Menu