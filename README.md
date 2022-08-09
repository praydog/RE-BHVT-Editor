# RE Engine Behavior Tree Editor

https://cursey.github.io/reframework-book/bhvt_editor/bhvt_editor.html

## Initial warning
This is very work-in-progress. It requires the [behaviortrees-fsm](https://github.com/praydog/REFramework/tree/behaviortrees-fsm) branch of REFramework to function. This can be compiled manually or a build of it can be downloaded from the [Actions](https://github.com/praydog/REFramework/actions) page of REFramework.

## Saving/Loading of Trees at Runtime
### ✅ Supported Tree Objects
* Actions (including custom Lua code)
* Conditions (including custom Lua code)
* Transition Events (including custom Lua code)

### ✅ Supported Fields/Properties
* Most primitive types (ints/enums/floats/etc...)
* System.Guid
* via.vec2/3/4

### ❌ Not (yet) Supported Fields/Properties
* Arrays/Lists (System.Array/System.Collections.Generic.List.*)
* Pointers to other managed objects
* Unknown ValueTypes

~~### 🕘 Coming Soon~~ Added
* Saving/loading of new nodes (enlarging/~~shrinking~~ the node array)

## Lua Driven Objects
These objects can be hooked to provide extended functionality that did not exist in the base game using Lua. 

Optionally, dummy versions of them can be inserted to have completely unique functionality that is ran within Lua.

### ✅ Supported Tree/Node Objects
* Actions
  * `start`
    * Ran every time the node is ran, once
  * `update`
    * Ran every frame that the node is active
  * `end`
    * Ran every time the node ends/transitions to another state, once
* Conditions
  * `evaluate`
    * Ran every frame that the node is active, returning `true` causes the node to transition into the condition's associated state
* Transition Events
  * `execute`
    * Ran for specific transitions into another state, once
    * Multiple transition events can run during a single transition

## Examples

### The UI
https://user-images.githubusercontent.com/2909949/178182705-7f4e31bb-9be4-4a9f-8a9e-951a9668da32.mp4

### Using Lua driven condition evaluators to run on-hit effects for all child nodes
https://user-images.githubusercontent.com/2909949/178722895-0c521cc6-004f-4ef9-9133-39112cfdf7f6.mp4

### Using Lua driven condition evaluators to dynamically adjust the game speed on hit and play on hit effects
https://user-images.githubusercontent.com/2909949/178723228-73cfd435-16b7-4f57-92f2-67a4f35a46e3.mp4

### Adding custom actions/effects to specific nodes
https://user-images.githubusercontent.com/2909949/178724426-5feb9624-c071-42b6-919a-f9efc037b04c.mp4


# Thanks
To the [imnodes](https://github.com/Nelarius/imnodes) developers for creating the library for rendering the nodes & graph.
