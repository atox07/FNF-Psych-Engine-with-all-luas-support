package states.editors;

import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import flash.net.FileFilter;
import haxe.Json;
import objects.TypedAlphabet;
import cutscenes.DialogueBoxPsych;
import cutscenes.DialogueCharacter;
import states.editors.content.Prompt;
#if MODS_ALLOWED
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

class DialoguePixelEditorState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent
{
	var characterLeft:FlxSprite;
	var characterRight:FlxSprite;
	var box:FlxSprite;
	var handSelect:FlxSprite;
	var bgFade:FlxSprite;

	var swagDialogue:FlxText;
	var dropText:FlxText;

	var selectedText:FlxText;
	var dialogueFile:DialogueFile = null;
	var curSelected:Int = 0;
	var unsavedProgress:Bool = false;

	var UI_box:PsychUIBox;
	var characterInputText:PsychUIInputText;
	var lineInputText:PsychUIInputText;
	var speedStepper:PsychUINumericStepper;
	var soundInputText:PsychUIInputText;

	override function create()
	{
		persistentUpdate = persistentDraw = true;
		FlxG.camera.bgColor = 0xFF151528;

		dialogueFile = {
			dialogue: [
				{
					portrait: 'senpai-mad',
					expression: 'enter',
					text: "Not bad for an ugly worm.",
					boxState: 'pixel-roses',
					speed: 0.04,
					sound: 'pixelText'
				},
				{
					portrait: 'bf-pixel',
					expression: 'enter',
					text: "Bop beep be be skdoo bep!",
					boxState: 'pixel-roses',
					speed: 0.04,
					sound: 'pixelText'
				}
			],
			isPixel: true,
			boxType: 'pixel-roses',
			bgFadeColor: '#B3DFD8'
		};

		// 1. Sfondo Pastello bgFade Week 6
		bgFade = new FlxSprite(-200, -200).makeGraphic(Std.int(FlxG.width * 1.5), Std.int(FlxG.height * 1.5), 0xFFB3DFD8);
		bgFade.scrollFactor.set();
		bgFade.alpha = 0.7;
		add(bgFade);

		// 2. Ritratti Pixel
		characterLeft = new FlxSprite(60, 160);
		if (Paths.fileExists('images/weeb/pixelUI/dialogueBox-senpaiMad.png', IMAGE))
		{
			characterLeft.frames = Paths.getSparrowAtlas('weeb/pixelUI/dialogueBox-senpaiMad');
			characterLeft.animation.addByPrefix('enter', 'SENPAI ANGRY IMPACT SPEECH', 24, false);
			characterLeft.animation.play('enter');
		}
		characterLeft.scale.set(5.4, 5.4);
		characterLeft.updateHitbox();
		characterLeft.antialiasing = false;
		add(characterLeft);

		characterRight = new FlxSprite(740, 170);
		if (Paths.fileExists('images/weeb/bfPortrait.png', IMAGE))
		{
			characterRight.frames = Paths.getSparrowAtlas('weeb/bfPortrait');
			characterRight.animation.addByPrefix('enter', 'Boyfriend portrait enter', 24, false);
			characterRight.animation.play('enter');
		}
		characterRight.scale.set(5.4, 5.4);
		characterRight.updateHitbox();
		characterRight.antialiasing = false;
		add(characterRight);

		// 3. Textbox Pixel autentica
		box = new FlxSprite(-20, 45);
		reloadBoxGraphic('pixel-roses');
		add(box);

		// 4. Manina cursore
		handSelect = new FlxSprite(1042, 590);
		if (Paths.fileExists('images/weeb/pixelUI/hand_textbox.png', IMAGE))
		{
			handSelect.loadGraphic(Paths.image('weeb/pixelUI/hand_textbox'));
		}
		handSelect.scale.set(5.4, 5.4);
		handSelect.updateHitbox();
		handSelect.antialiasing = false;
		add(handSelect);

		// 5. Testi Pixel (dropText ombra e swagDialogue)
		dropText = new FlxText(242, 502, Std.int(FlxG.width * 0.6), "", 32);
		dropText.font = Paths.font("pixel.otf");
		dropText.color = 0xFFD89494;
		dropText.borderSize = 0;
		dropText.antialiasing = false;
		add(dropText);

		swagDialogue = new FlxText(240, 500, Std.int(FlxG.width * 0.6), "", 32);
		swagDialogue.font = Paths.font("pixel.otf");
		swagDialogue.color = 0xFF3F2021;
		swagDialogue.borderSize = 0;
		swagDialogue.antialiasing = false;
		add(swagDialogue);

		selectedText = new FlxText(10, 10, FlxG.width - 20, '', 16);
		selectedText.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		selectedText.borderSize = 2;
		add(selectedText);

		addEditorUI();
		changeLine(0);

		FlxG.mouse.visible = true;
		super.create();
	}

	function addEditorUI()
	{
		UI_box = new PsychUIBox(FlxG.width - 290, 10, 280, 260, ['Pixel Dialogue']);
		UI_box.scrollFactor.set();

		var tab = UI_box.getTab('Pixel Dialogue').menu;

		characterInputText = new PsychUIInputText(10, 25, 120, 'senpai-mad', 8);
		speedStepper = new PsychUINumericStepper(140, 25, 0.005, 0.04, 0.01, 0.5, 3);

		lineInputText = new PsychUIInputText(10, 75, 250, '', 8);
		lineInputText.onPressEnter = function(e)
		{
			if (e.shiftKey)
			{
				lineInputText.text += '\n';
				lineInputText.caretIndex++;
			}
			else
				PsychUIInputText.focusOn = null;
		};

		soundInputText = new PsychUIInputText(10, 125, 120, 'pixelText', 8);

		var saveButton = new PsychUIButton(10, 175, "Salva JSON", function() {
			saveDialogue();
		});

		var loadButton = new PsychUIButton(100, 175, "Carica JSON", function() {
			loadDialogue();
		});

		tab.add(new FlxText(10, 8, 0, 'Personaggio:'));
		tab.add(new FlxText(140, 8, 0, 'Velocità:'));
		tab.add(characterInputText);
		tab.add(speedStepper);

		tab.add(new FlxText(10, 58, 0, 'Testo del Dialogo:'));
		tab.add(lineInputText);

		tab.add(new FlxText(10, 108, 0, 'Suono Typewriter:'));
		tab.add(soundInputText);

		tab.add(saveButton);
		tab.add(loadButton);

		add(UI_box);
	}

	function reloadBoxGraphic(boxType:String)
	{
		var boxAsset:String = 'weeb/pixelUI/dialogueBox-pixel';
		if (boxType == 'pixel-roses')
			boxAsset = 'weeb/pixelUI/dialogueBox-senpaiMad';
		else if (boxType == 'pixel-thorns')
			boxAsset = 'weeb/pixelUI/dialogueBox-evil';

		if (Paths.fileExists('images/' + boxAsset + '.png', IMAGE))
		{
			box.frames = Paths.getSparrowAtlas(boxAsset);
			box.animation.addByPrefix('normalOpen', 'Text Box Appear', 24, false);
			box.animation.addByIndices('normal', 'Text Box Appear instance 1', [4], "", 24);
			box.animation.play('normal');
		}
		box.scale.set(5.4, 5.4);
		box.updateHitbox();
		box.screenCenter(X);
		box.antialiasing = false;
	}

	function changeLine(change:Int = 0)
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, dialogueFile.dialogue.length - 1);
		var curLine = dialogueFile.dialogue[curSelected];

		characterInputText.text = curLine.portrait;
		lineInputText.text = curLine.text;
		speedStepper.value = curLine.speed != null ? curLine.speed : 0.04;
		soundInputText.text = curLine.sound != null ? curLine.sound : 'pixelText';

		swagDialogue.text = curLine.text;
		dropText.text = curLine.text;

		var isBf:Bool = (curLine.portrait.indexOf('bf') != -1);
		characterLeft.visible = !isBf;
		characterRight.visible = isBf;

		selectedText.text = 'Riga: (' + (curSelected + 1) + ' / ' + dialogueFile.dialogue.length + ') - Premi A/D o LEFT/RIGHT per scorrere';
	}

	public function UIEvent(id:String, sender:Dynamic)
	{
		if (id == PsychUIInputText.CHANGE_EVENT && sender == lineInputText)
		{
			dialogueFile.dialogue[curSelected].text = lineInputText.text;
			swagDialogue.text = lineInputText.text;
			dropText.text = lineInputText.text;
			unsavedProgress = true;
		}
		else if (id == PsychUIInputText.CHANGE_EVENT && sender == characterInputText)
		{
			dialogueFile.dialogue[curSelected].portrait = characterInputText.text;
			var isBf:Bool = (characterInputText.text.indexOf('bf') != -1);
			characterLeft.visible = !isBf;
			characterRight.visible = isBf;
			unsavedProgress = true;
		}
		else if (id == PsychUINumericStepper.CHANGE_EVENT && sender == speedStepper)
		{
			dialogueFile.dialogue[curSelected].speed = speedStepper.value;
			unsavedProgress = true;
		}
		else if (id == PsychUIInputText.CHANGE_EVENT && sender == soundInputText)
		{
			dialogueFile.dialogue[curSelected].sound = soundInputText.text;
			unsavedProgress = true;
		}
	}

	override function update(elapsed:Float)
	{
		if (PsychUIInputText.focusOn == null)
		{
			if (FlxG.keys.justPressed.ESCAPE)
			{
				MusicBeatState.switchState(new states.editors.MasterEditorMenu());
				return;
			}
			if (FlxG.keys.justPressed.D || FlxG.keys.justPressed.RIGHT)
			{
				changeLine(1);
			}
			else if (FlxG.keys.justPressed.A || FlxG.keys.justPressed.LEFT)
			{
				changeLine(-1);
			}
			else if (FlxG.keys.justPressed.P)
			{
				dialogueFile.dialogue.insert(curSelected + 1, {
					portrait: 'bf-pixel',
					expression: 'enter',
					text: 'Nuova battuta...',
					boxState: 'pixel-roses',
					speed: 0.04,
					sound: 'pixelText'
				});
				changeLine(1);
			}
			else if (FlxG.keys.justPressed.O && dialogueFile.dialogue.length > 1)
			{
				dialogueFile.dialogue.remove(dialogueFile.dialogue[curSelected]);
				changeLine(-1);
			}
		}
		super.update(elapsed);
	}

	var _file:FileReference;
	function saveDialogue()
	{
		var data = Json.stringify(dialogueFile, "\t");
		_file = new FileReference();
		_file.save(data, "dialogue.json");
	}

	function loadDialogue()
	{
		var jsonFilter:FileFilter = new FileFilter('JSON', 'json');
		_file = new FileReference();
		_file.addEventListener(Event.SELECT, function(_) {
			#if sys
			@:privateAccess
			if (_file.__path != null)
			{
				var content = File.getContent(_file.__path);
				dialogueFile = Json.parse(content);
				changeLine(0);
			}
			#end
		});
		_file.browse([jsonFilter]);
	}
}
