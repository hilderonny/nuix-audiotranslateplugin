# nuix-audiotranslateplugin

[NUIX](https://www.nuix.com/) plugin for audio translation via distributed workers. Uses [Task Bridge](https://github.com/hilderonny/taskbridge) together with [Transcribe](https://github.com/hilderonny/taskworker-transcribe) and [Translate](https://github.com/hilderonny/taskworker-translate) workers for distributing and doing the work.

## Output

Using this plugin on selected media itemseach item will get the following custom metadata.

|Property|Description|
|-|-|
|`Audio Language`|First language detected in the media file. If the file contains mutliple languages, only the first one is detected.|
|`Audio Transcription`|Transcribed text of the media file in its original language|
|`Audio Translation`|Text in german|

## Installation

First download an install [NUIX](https://www.nuix.com/).

Next copy the entire folder `transcription.nuixscript` into the plugin directory of yout NUIX installation.

## Usage

1. Create a NUIX case and add some data
1. Select audio or video items (checking the checkbox)
1. Right-Click an Run `Plugin -> Audio transcription and translation`
