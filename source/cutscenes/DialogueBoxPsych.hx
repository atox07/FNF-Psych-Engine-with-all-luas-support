package cutscenes;

import haxe.Json;
import openfl.utils.Assets;
import objects.TypedAlphabet;
import cutscenes.DialogueCharacter;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
#if MODS_ALLOWED
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

typedef DialogueFile =
{
	var dialogue:Array<DialogueLine>;
	@:optional var isPixel:Null<Bool>;
	@:optional var boxType:Null<String>;
	@:optional var bgFadeColor:Null<String>;
}

typedef DialogueLine =
{
	var portrait:Null<String>;
	var expression:Null<String>;
	var text:Null<String>;
	var boxState:Null<String>;
	var speed:Null<Float>;
	@:optional var sound:Null<String>;
}

class DialogueBoxPsych extends FlxSpriteGroup
{
	public static var DEFAULT_TEXT_X = 175;
	public static var DEFAULT_TEXT_Y = 460;
	public static var LONG_TEXT_ADD = 24;

	var scrollSpeed = 4000;

	var dialogue:TypedAlphabet;
	var dialogueList:DialogueFile = null;

	public var finishThing:Void->Void;
	public var nextDialogueThing:Void->Void = null;
	public var skipDialogueThing:Void->Void = null;

	var bgFade:FlxSprite = null;
	var box:FlxSprite;
	var textToType:String = '';

	var arrayCharacters:Array<DialogueCharacter> = [];

	var currentText:Int = 0;
	var offsetPos:Float = -600;
	var skipText:FlxText;

	var textBoxTypes:Array<String> = ['normal', 'angry'];

	var curCharacter:String = "";

	// Variabili di supporto per la modalità Pixel (Week 6)
	public var isPixel:Bool = false;
	public var dropText:FlxText = null;
	public var pixelDialogueText:FlxText = null;
	public var handSelect:FlxSprite = null;

	public function new(dialogueList:DialogueFile, ?song:String = null)
	{
		super();

		// Precaricamento suoni
		Paths.sound('dialogue');
		Paths.sound('dialogueClose');
		Paths.sound('pixelText');
		Paths.sound('clickText');
		Paths.sound('ANGRY_TEXT_BOX');

		if (song != null && song != '')
		{
			FlxG.sound.playMusic(Paths.music(song), 0);
			FlxG.sound.music.fadeIn(2, 0, 1);
		}

		// Rileva se il dialogo è in modalità Pixel
		if (dialogueList.isPixel == true || (dialogueList.boxType != null && dialogueList.boxType.startsWith('pixel')))
		{
			isPixel = true;
		}

		// Colore overlay sfondo (bgFade)
		var fadeColor:FlxColor = FlxColor.WHITE;
		if (isPixel)
		{
			if (dialogueList.bgFadeColor != null && dialogueList.bgFadeColor.length > 0)
				fadeColor = FlxColor.fromString(dialogueList.bgFadeColor);
			else
				fadeColor = 0xFFB3DFD8;
		}

		bgFade = new FlxSprite(-500, -500).makeGraphic(FlxG.width * 2, FlxG.height * 2, fadeColor);
		bgFade.scrollFactor.set();
		bgFade.visible = true;
		bgFade.alpha = 0;
		add(bgFade);

		this.dialogueList = dialogueList;
		spawnCharacters();

		if (isPixel)
		{
			// Caricamento Textbox Week 6 con scaling 5.4 e antialiasing disattivato
			var boxImage:String = 'weeb/pixelUI/dialogueBox-pixel';
			if (dialogueList.boxType == 'pixel-roses')
				boxImage = 'weeb/pixelUI/dialogueBox-senpaiMad';
			else if (dialogueList.boxType == 'pixel-thorns')
				boxImage = 'weeb/pixelUI/dialogueBox-evil';

			box = new FlxSprite(-20, 45);
			box.frames = Paths.getSparrowAtlas(boxImage);
			box.scrollFactor.set();
			box.animation.addByPrefix('normal', 'Text Box Appear instance 1', 24);
			box.animation.addByPrefix('normalOpen', 'Text Box Appear', 24, false);
			box.animation.play('normalOpen', true);
			box.scale.set(5.4, 5.4);
			box.updateHitbox();
			box.screenCenter(X);
			box.antialiasing = false;
			add(box);

			// Manina pixel che indica la fine del testo
			handSelect = new FlxSprite(1042, 590);
			if (Paths.fileExists('images/weeb/pixelUI/hand_textbox.png', IMAGE))
				handSelect.loadGraphic(Paths.image('weeb/pixelUI/hand_textbox'));
			handSelect.scale.set(5.4, 5.4);
			handSelect.updateHitbox();
			handSelect.antialiasing = false;
			handSelect.visible = false;
			add(handSelect);

			// Testo Pixel sdoppiato con ombra (dropText) e testo principale (pixelDialogueText)
			dropText = new FlxText(242, 502, Std.int(FlxG.width * 0.6), "", 32);
			dropText.font = Paths.font("pixel.otf");
			dropText.color = (dialogueList.boxType == 'pixel-thorns') ? 0xFF000000 : 0xFFD89494;
			dropText.borderSize = 0;
			dropText.antialiasing = false;
			add(dropText);

			pixelDialogueText = new FlxText(240, 500, Std.int(FlxG.width * 0.6), "", 32);
			pixelDialogueText.font = Paths.font("pixel.otf");
			pixelDialogueText.color = (dialogueList.boxType == 'pixel-thorns') ? 0xFFFFFFFF : 0xFF3F2021;
			pixelDialogueText.borderSize = 0;
			pixelDialogueText.antialiasing = false;
			add(pixelDialogueText);
		}
		else
		{
			// Textbox HD Speech Bubble standard per dialoghi normali
			box = new FlxSprite(70, 370);
			box.antialiasing = ClientPrefs.data.antialiasing;
			box.frames = Paths.getSparrowAtlas('speech_bubble');
			box.scrollFactor.set();
			box.animation.addByPrefix('normal', 'speech bubble normal', 24);
			box.animation.addByPrefix('normalOpen', 'Speech Bubble Normal Open', 24, false);
			box.animation.addByPrefix('angry', 'AHH speech bubble', 24);
			box.animation.addByPrefix('angryOpen', 'speech bubble loud open', 24, false);
			box.animation.addByPrefix('center-normal', 'speech bubble middle', 24);
			box.animation.addByPrefix('center-normalOpen', 'Speech Bubble Middle Open', 24, false);
			box.animation.addByPrefix('center-angry', 'AHH Speech Bubble middle', 24);
			box.animation.addByPrefix('center-angryOpen', 'speech bubble Middle loud open', 24, false);
			box.animation.play('normal', true);
			box.visible = false;
			box.setGraphicSize(Std.int(box.width * 0.9));
			box.updateHitbox();
			add(box);

			daText = new TypedAlphabet(DEFAULT_TEXT_X, DEFAULT_TEXT_Y, '');
			daText.setScale(0.7);
			add(daText);
		}

		skipText = new FlxText(FlxG.width - 320, FlxG.height - 30, 300, Language.getPhrase('dialogue_skip', 'Press BACK to Skip'), 16);
		skipText.setFormat(null, 16, FlxColor.WHITE, RIGHT, OUTLINE_FAST, FlxColor.BLACK);
		skipText.borderSize = 2;
		add(skipText);

		startNextDialog();
	}

	var dialogueStarted:Bool = false;
	var dialogueEnded:Bool = false;

	public static var LEFT_CHAR_X:Float = -60;
	public static var RIGHT_CHAR_X:Float = -100;
	public static var DEFAULT_CHAR_Y:Float = 60;

	function spawnCharacters()
	{
		var charsMap:Map<String, Bool> = new Map<String, Bool>();
		for (i in 0...dialogueList.dialogue.length)
		{
			if (dialogueList.dialogue[i] != null)
			{
				var charToAdd:String = dialogueList.dialogue[i].portrait;
				if (!charsMap.exists(charToAdd) || !charsMap.get(charToAdd))
				{
					charsMap.set(charToAdd, true);
				}
			}
		}

		for (individualChar in charsMap.keys())
		{
			var x:Float = LEFT_CHAR_X;
			var y:Float = DEFAULT_CHAR_Y;
			var char:DialogueCharacter = new DialogueCharacter(x + offsetPos, y, individualChar);

			// Se il dialogo è pixel o il personaggio è Week 6, disattiva antialiasing e scala 5.4x
			if (isPixel || individualChar.indexOf('pixel') != -1 || individualChar.indexOf('weeb') != -1)
			{
				char.antialiasing = false;
				char.scale.set(5.4, 5.4);
			}
			else
			{
				char.setGraphicSize(Std.int(char.width * DialogueCharacter.DEFAULT_SCALE * char.jsonFile.scale));
			}
			char.updateHitbox();
			char.scrollFactor.set();
			char.alpha = 0.00001;
			add(char);

			var saveY:Bool = false;
			switch (char.jsonFile.dialogue_pos)
			{
				case 'center':
					char.x = FlxG.width / 2;
					char.x -= char.width / 2;
					y = char.y;
					char.y = FlxG.height + 50;
					saveY = true;
				case 'right':
					x = FlxG.width - char.width + RIGHT_CHAR_X;
					char.x = x - offsetPos;
			}
			x += char.jsonFile.position[0];
			y += char.jsonFile.position[1];
			char.x += char.jsonFile.position[0];
			char.y += char.jsonFile.position[1];
			char.startingPos = (saveY ? y : x);
			arrayCharacters.push(char);
		}
	}

	var daText:TypedAlphabet = null;
	var ignoreThisFrame:Bool = true;

	public var closeSound:String = 'dialogueClose';
	public var closeVolume:Float = 1;

	// Gestione Typewriter Pixel
	var pixelTypeTimer:Float = 0;
	var pixelCharIndex:Int = 0;
	var targetPixelText:String = "";
	var pixelSpeed:Float = 0.04;
	var isPixelTyping:Bool = false;

	override function update(elapsed:Float)
	{
		if (ignoreThisFrame)
		{
			ignoreThisFrame = false;
			super.update(elapsed);
			return;
		}

		// Effetto macchina da scrivere (typewriter) per font pixel
		if (isPixel && isPixelTyping)
		{
			pixelTypeTimer += elapsed;
			if (pixelTypeTimer >= pixelSpeed)
			{
				pixelTypeTimer = 0;
				pixelCharIndex++;
				if (pixelCharIndex <= targetPixelText.length)
				{
					pixelDialogueText.text = targetPixelText.substr(0, pixelCharIndex);
					dropText.text = pixelDialogueText.text;
					if (pixelCharIndex % 2 == 1)
						FlxG.sound.play(Paths.sound('pixelText'), 0.6);
				}
				else
				{
					isPixelTyping = false;
					if (handSelect != null)
						handSelect.visible = true;
				}
			}
		}

		if (!dialogueEnded)
		{
			bgFade.alpha += 0.5 * elapsed;
			if (bgFade.alpha > 0.7)
				bgFade.alpha = 0.7;

			var back:Bool = #if android FlxG.android.justReleased.BACK || #end Controls.instance.BACK;
			if ((TouchUtil.justPressed || Controls.instance.ACCEPT) || back)
			{
				var isFinished:Bool = isPixel ? !isPixelTyping : daText.finishedText;
				if (!isFinished && !back)
				{
					// Se sta ancora scrivendo, completa subito la frase
					if (isPixel)
					{
						isPixelTyping = false;
						pixelDialogueText.text = targetPixelText;
						dropText.text = targetPixelText;
						if (handSelect != null)
							handSelect.visible = true;
					}
					else
					{
						daText.finishText();
					}
					if (skipDialogueThing != null)
					{
						skipDialogueThing();
					}
				}
				else if (back || currentText >= dialogueList.dialogue.length)
				{
					// Fine del dialogo
					dialogueEnded = true;
					if (isPixel)
					{
						FlxTween.tween(box, {alpha: 0}, 0.5);
						FlxTween.tween(bgFade, {alpha: 0}, 0.5);
						if (pixelDialogueText != null) pixelDialogueText.visible = false;
						if (dropText != null) dropText.visible = false;
						if (handSelect != null) handSelect.visible = false;
					}
					else
					{
						for (i in 0...textBoxTypes.length)
						{
							var checkArray:Array<String> = ['', 'center-'];
							var animName:String = box.animation.curAnim.name;
							for (j in 0...checkArray.length)
							{
								if (animName == checkArray[j] + textBoxTypes[i] || animName == checkArray[j] + textBoxTypes[i] + 'Open')
								{
									box.animation.play(checkArray[j] + textBoxTypes[i] + 'Open', true);
								}
							}
						}
						box.animation.curAnim.curFrame = box.animation.curAnim.frames.length - 1;
						box.animation.curAnim.reverse();
						if (daText != null)
						{
							daText.kill();
							remove(daText);
							daText.destroy();
						}
					}
					skipText.visible = false;
					FlxG.sound.music.fadeOut(1, 0, (_) -> FlxG.sound.music.stop());
				}
				else
				{
					startNextDialog();
				}
				FlxG.sound.play(Paths.sound(isPixel ? 'clickText' : closeSound), closeVolume);
			}

			// Posizionamento ritratti e dissolvenza
			if (lastCharacter != -1 && arrayCharacters.length > 0)
			{
				for (i in 0...arrayCharacters.length)
				{
					var char = arrayCharacters[i];
					if (char != null)
					{
						if (i != lastCharacter)
						{
							char.alpha -= 3 * elapsed;
							if (char.alpha < 0.00001) char.alpha = 0.00001;
						}
						else
						{
							char.alpha += 3 * elapsed;
							if (char.alpha > 1) char.alpha = 1;
						}
					}
				}
			}
		}
		else
		{
			// Chiusura finale
			if (bgFade != null)
			{
				bgFade.alpha -= 0.5 * elapsed;
				if (bgFade.alpha <= 0)
				{
					bgFade.kill();
					remove(bgFade);
					bgFade.destroy();
					bgFade = null;
				}
			}

			if (bgFade == null)
			{
				finishThing();
				kill();
			}
		}
		super.update(elapsed);
	}

	var lastCharacter:Int = -1;
	var lastBoxType:String = '';

	function startNextDialog():Void
	{
		var curDialogue:DialogueLine = null;
		do
		{
			curDialogue = dialogueList.dialogue[currentText];
		}
		while (curDialogue == null);

		if (curDialogue.text == null || curDialogue.text.length < 1)
			curDialogue.text = ' ';
		if (curDialogue.boxState == null)
			curDialogue.boxState = 'normal';
		if (curDialogue.speed == null || Math.isNaN(curDialogue.speed))
			curDialogue.speed = 0.04;

		var character:Int = 0;
		box.visible = true;
		for (i in 0...arrayCharacters.length)
		{
			if (arrayCharacters[i].curCharacter == curDialogue.portrait)
			{
				character = i;
				break;
			}
		}

		lastCharacter = character;

		if (isPixel)
		{
			targetPixelText = curDialogue.text;
			pixelCharIndex = 0;
			pixelTypeTimer = 0;
			pixelSpeed = curDialogue.speed;
			isPixelTyping = true;
			if (handSelect != null) handSelect.visible = false;
			pixelDialogueText.text = "";
			dropText.text = "";
		}
		else
		{
			daText.text = curDialogue.text;
			daText.delay = curDialogue.speed;
			daText.sound = curDialogue.sound;
			if (daText.sound == null || daText.sound.trim() == '')
				daText.sound = 'dialogue';
		}

		var char:DialogueCharacter = arrayCharacters[character];
		if (char != null)
		{
			char.playAnim(curDialogue.expression, false);
		}
		currentText++;

		if (nextDialogueThing != null)
		{
			nextDialogueThing();
		}
	}

	inline public static function parseDialogue(path:String):DialogueFile
	{
		#if MODS_ALLOWED
		return cast(FileSystem.exists(path)) ? Json.parse(File.getContent(path)) : dummy();
		#else
		return cast(Assets.exists(path, TEXT)) ? Json.parse(Assets.getText(path)) : dummy();
		#end
	}

	inline public static function dummy():DialogueFile
	{
		return {
			dialogue: [
				{
					expression: "talk",
					text: "DIALOGUE NOT FOUND",
					boxState: "normal",
					speed: 0.05,
					portrait: "bf"
				}
			],
			isPixel: false
		};
	}

	public static function updateBoxOffsets(box:FlxSprite)
	{
		box.centerOffsets();
		box.updateHitbox();
		if (box.animation.curAnim.name.startsWith('angry'))
		{
			box.offset.set(50, 65);
		}
		else if (box.animation.curAnim.name.startsWith('center-angry'))
		{
			box.offset.set(50, 30);
		}
		else
		{
			box.offset.set(10, 0);
		}

		if (!box.flipX)
			box.offset.y += 10;
	}
}
