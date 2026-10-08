package backend;

import flixel.FlxBasic;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;
import haxe.ds.ObjectMap;

import backend.BaseStage;
import backend.StageData;
import states.PlayState;

#if LUA_ALLOWED
import psychlua.FunkinLua;
#end
#if HSCRIPT_ALLOWED
import psychlua.HScript;
#end

/**
 * Evento nativo "Change Stage" (come Change Character).
 *
 * - Gli stage usati nella chart vengono creati TUTTI all'avvio della song
 *   (nascosti) -> al cambio si fa solo show/hide, zero lag.
 * - Funziona con: stage base (classi states.stages.*), stage con "objects"
 *   nel json (Stage Editor), stage moddati .lua e .hx.
 *
 * Uso da chart:   Event "Change Stage"
 *   Value 1: nome stage (es. spooky)
 *   Value 2: flag opzionali separati da virgola:
 *            nochars, nozoom, nocam, nogf
 * Uso da Lua:     triggerEvent('Change Stage', 'spooky', '')
 */
private class StageSlot
{
	public var name:String;
	public var members:Array<FlxBasic> = [];
	public var stages:Array<BaseStage> = [];
	#if LUA_ALLOWED
	public var luas:Array<FunkinLua> = [];
	#end
	#if HSCRIPT_ALLOWED
	public var hscripts:Array<HScript> = [];
	#end

	public function new(name:String)
	{
		this.name = name;
	}

	public function isEmpty():Bool
	{
		var empty = members.length == 0 && stages.length == 0;
		#if LUA_ALLOWED
		empty = empty && luas.length == 0;
		#end
		#if HSCRIPT_ALLOWED
		empty = empty && hscripts.length == 0;
		#end
		return empty;
	}
}

class StageChanger
{
	// nome stage base -> possibili nomi della classe in states.stages
	static var CLASS_NAMES:Map<String, Array<String>> = [
		'stage' => ['StageWeek1'],
		'spooky' => ['Spooky'],
		'philly' => ['Philly', 'PhillyNice'],
		'limo' => ['Limo'],
		'mall' => ['Mall'],
		'mallEvil' => ['MallEvil'],
		'school' => ['School'],
		'schoolEvil' => ['SchoolEvil'],
		'tank' => ['Tank'],
		'phillyStreets' => ['PhillyStreets'],
		'phillyBlazin' => ['PhillyBlazin']
	];

	var game:PlayState;
	var slots:Map<String, StageSlot> = new Map();
	var queued:Array<String> = [];

	public var current(default, null):String = '';

	public function new(game:PlayState)
	{
		this.game = game;
	}

	// ------------------------------------------------------------------
	// API pubblica (chiamata da PlayState)
	// ------------------------------------------------------------------

	/** Da eventPushed: segna lo stage da precaricare. */
	public function queue(name:String):Void
	{
		name = StringTools.trim(name == null ? '' : name);
		if (name != '' && queued.indexOf(name) == -1)
			queued.push(name);
	}

	/** A fine create(): registra lo stage iniziale della song, così si può nascondere. */
	public function captureInitial():Void
	{
		if (current != '') return;
		current = PlayState.curStage;

		var slot = new StageSlot(current);
		var gfIdx = game.members.indexOf(game.gfGroup);
		var bfIdx = game.members.indexOf(game.boyfriendGroup);

		for (i in 0...game.members.length)
		{
			var o = game.members[i];
			if (o == null || !o.exists) continue;
			if (o == game.gfGroup || o == game.dadGroup || o == game.boyfriendGroup) continue;
			if (!onGameCamera(o)) continue; // HUD, debug, ecc. restano

			// tutto quello che sta dietro ai personaggi è stage
			var isBack = gfIdx >= 0 && i < gfIdx;
			// davanti ai personaggi: solo sprite singoli sulla camera di gioco (foreground)
			var isFront = bfIdx >= 0 && i > bfIdx
				&& Std.isOfType(o, FlxSprite) && !Std.isOfType(o, FlxSpriteGroup);

			if (isBack || isFront) slot.members.push(o);
		}

		slot.stages = game.stages.copy();

		#if LUA_ALLOWED
		for (l in game.luaArray)
			if (l.scriptName != null && l.scriptName.indexOf('stages/' + current + '.lua') != -1)
				slot.luas.push(l);
		#end
		#if HSCRIPT_ALLOWED
		for (h in game.hscriptArray)
		{
			var origin:String = Reflect.field(h, 'origin');
			if (origin != null && origin.indexOf('stages/' + current + '.hx') != -1)
				slot.hscripts.push(h);
		}
		#end

		slots.set(current, slot);
	}

	/** A fine create(): crea (nascosti) tutti gli stage della chart. */
	public function preloadQueued():Void
	{
		for (n in queued)
		{
			if (slots.exists(n)) continue;
			var slot = build(n);
			if (slot != null)
			{
				setSlot(slot, false);
				slots.set(n, slot);
			}
		}
		queued = [];
	}

	/** Cambio stage (evento "Change Stage"). */
	public function change(name:String, ?flagsStr:String = ''):Void
	{
		name = StringTools.trim(name == null ? '' : name);
		if (name == '') return;

		if (current == '') captureInitial(); // evento lanciato senza essere nella chart
		if (name == current) return;

		var flags = parseFlags(flagsStr);

		var next = slots.get(name);
		if (next == null)
		{
			// non era stato precaricato (es. triggerEvent da script): lo crea ora
			next = build(name);
			if (next == null)
			{
				warn('stage "' + name + '" non trovato (nessuna classe base, json objects, .lua o .hx).');
				return;
			}
			setSlot(next, false);
			slots.set(name, next);
		}

		var prev = slots.get(current);
		if (prev != null) setSlot(prev, false);
		setSlot(next, true);
		current = name;

		applyStageData(StageData.getStageFile(name), flags);
		game.moveCameraSection();
	}

	/** Da PlayState.destroy(): chiude gli script degli stage nascosti. */
	public function destroy():Void
	{
		#if LUA_ALLOWED
		for (s in slots)
			for (l in s.luas)
				if (game.luaArray.indexOf(l) == -1)
					l.stop();
		#end
		slots.clear();
	}

	// ------------------------------------------------------------------
	// Costruzione di uno stage
	// ------------------------------------------------------------------
	function build(name:String):StageSlot
	{
		var sd:Dynamic = StageData.getStageFile(name);
		var saved = saveState();

		// cartella assets giusta (week2, week3, ...) per trovare le immagini
		var prevLevel = Paths.currentLevel;
		var dir:String = (sd != null && sd.directory != null) ? sd.directory : '';
		Paths.currentLevel = dir.toLowerCase();

		var slot = new StageSlot(name);
		var before = snapshot();
		var stagesBefore = game.stages.length;
		#if LUA_ALLOWED
		var luaBefore = game.luaArray.length;
		#end
		#if HSCRIPT_ALLOWED
		var hBefore = game.hscriptArray.length;
		#end

		// 1) classe Haxe dello stage base (se esiste)
		createBaseStage(name);

		// gli add() fatti in create() finiscono in fondo: li riporta dietro ai personaggi
		var bfIdx = game.members.indexOf(game.boyfriendGroup);
		for (o in newSince(before))
		{
			if (game.members.indexOf(o) > bfIdx)
			{
				game.remove(o, true);
				game.insert(game.members.indexOf(game.gfGroup), o);
			}
		}

		// 2) eventi già caricati + createPost
		var newStages = game.stages.slice(stagesBefore);
		for (st in newStages)
		{
			for (ev in game.eventNotes)
				callIfExists(st, 'eventPushed', [ev]);
			st.createPost();
		}

		// 3) stage da json ("objects" dello Stage Editor) oppure script
		var objs:Array<Dynamic> = (sd != null) ? sd.objects : null;
		if (objs != null && objs.length > 0)
		{
			try
			{
				var cls = Type.resolveClass('backend.StageData');
				var fn = Reflect.field(cls, 'addObjectsToState');
				var hideGf:Bool = (sd.hide_girlfriend == true);
				Reflect.callMethod(cls, fn, [objs, hideGf ? null : game.gfGroup, game.dadGroup, game.boyfriendGroup, game]);
			}
			catch (e:Dynamic)
			{
				warn('errore creando gli objects dello stage "' + name + '": ' + e);
			}
		}
		else
		{
			#if LUA_ALLOWED
			game.startLuasNamed('stages/' + name + '.lua');
			#end
			#if HSCRIPT_ALLOWED
			game.startHScriptsNamed('stages/' + name + '.hx');
			#end
		}

		// 4) onCreatePost degli script appena creati
		#if LUA_ALLOWED
		for (i in luaBefore...game.luaArray.length)
		{
			var l = game.luaArray[i];
			slot.luas.push(l);
			l.call('onCreatePost', []);
		}
		#end
		#if HSCRIPT_ALLOWED
		for (i in hBefore...game.hscriptArray.length)
		{
			var h = game.hscriptArray[i];
			slot.hscripts.push(h);
			callIfExists(h, 'executeFunction', ['onCreatePost', []]);
		}
		#end

		// 5) raccoglie tutto quello che è stato creato
		for (o in newSince(before))
			if (o.exists) slot.members.push(o);
		slot.stages = newStages;

		// 6) rimette a posto quello che lo stage ha toccato (zoom, camera, posizioni)
		restoreState(saved);
		Paths.currentLevel = prevLevel;

		if (slot.isEmpty()) return null;
		return slot;
	}

	function createBaseStage(name:String):Void
	{
		var names = CLASS_NAMES.get(name);
		if (names == null) return;
		for (n in names)
		{
			var cls = Type.resolveClass('states.stages.' + n);
			if (cls == null) continue;
			try
			{
				Type.createInstance(cls, []);
			}
			catch (e:Dynamic)
			{
				warn('errore creando lo stage base "' + name + '": ' + e);
			}
			return;
		}
	}

	// ------------------------------------------------------------------
	// Mostra / nascondi uno stage
	// ------------------------------------------------------------------
	function setSlot(s:StageSlot, on:Bool):Void
	{
		for (o in s.members)
			if (o != null) o.exists = on;

		for (st in s.stages)
		{
			st.exists = on;
			st.active = on;
		}

		// gli script nascosti non ricevono più callback (update, beat, ecc.)
		#if LUA_ALLOWED
		for (l in s.luas)
		{
			if (on)
			{
				if (game.luaArray.indexOf(l) == -1) game.luaArray.push(l);
			}
			else
				game.luaArray.remove(l);
		}
		#end
		#if HSCRIPT_ALLOWED
		for (h in s.hscripts)
		{
			if (on)
			{
				if (game.hscriptArray.indexOf(h) == -1) game.hscriptArray.push(h);
			}
			else
				game.hscriptArray.remove(h);
		}
		#end
	}

	// ------------------------------------------------------------------
	// Dati del json (posizioni, zoom, camera)
	// ------------------------------------------------------------------
	function applyStageData(sd:Dynamic, flags:Map<String, Bool>):Void
	{
		if (sd == null) return;

		if (!flags.exists('nochars'))
		{
			if (sd.boyfriend != null && sd.boyfriend.length >= 2)
			{
				game.BF_X = num(sd.boyfriend[0]);
				game.BF_Y = num(sd.boyfriend[1]);
				game.boyfriendGroup.setPosition(game.BF_X, game.BF_Y);
			}
			if (sd.opponent != null && sd.opponent.length >= 2)
			{
				game.DAD_X = num(sd.opponent[0]);
				game.DAD_Y = num(sd.opponent[1]);
				game.dadGroup.setPosition(game.DAD_X, game.DAD_Y);
			}
			if (sd.girlfriend != null && sd.girlfriend.length >= 2)
			{
				game.GF_X = num(sd.girlfriend[0]);
				game.GF_Y = num(sd.girlfriend[1]);
				game.gfGroup.setPosition(game.GF_X, game.GF_Y);
			}
		}

		if (!flags.exists('nogf'))
			game.gfGroup.visible = (sd.hide_girlfriend != true);

		if (!flags.exists('nozoom') && sd.defaultZoom != null)
			game.defaultCamZoom = num(sd.defaultZoom, game.defaultCamZoom);

		if (!flags.exists('nocam'))
		{
			if (sd.camera_boyfriend != null && sd.camera_boyfriend.length >= 2)
				game.boyfriendCameraOffset = [num(sd.camera_boyfriend[0]), num(sd.camera_boyfriend[1])];
			if (sd.camera_opponent != null && sd.camera_opponent.length >= 2)
				game.opponentCameraOffset = [num(sd.camera_opponent[0]), num(sd.camera_opponent[1])];
			if (sd.camera_girlfriend != null && sd.camera_girlfriend.length >= 2)
				game.girlfriendCameraOffset = [num(sd.camera_girlfriend[0]), num(sd.camera_girlfriend[1])];
			if (sd.camera_speed != null)
				game.cameraSpeed = num(sd.camera_speed, game.cameraSpeed);
		}
	}

	// salva/ripristina quello che uno stage appena creato potrebbe modificare
	function saveState():Dynamic
	{
		return {
			zoom: game.defaultCamZoom,
			speed: game.cameraSpeed,
			pixel: game.isPixelStage,
			bfCam: game.boyfriendCameraOffset.copy(),
			dadCam: game.opponentCameraOffset.copy(),
			gfCam: game.girlfriendCameraOffset.copy(),
			bfX: game.boyfriendGroup.x, bfY: game.boyfriendGroup.y,
			dadX: game.dadGroup.x, dadY: game.dadGroup.y,
			gfX: game.gfGroup.x, gfY: game.gfGroup.y,
			gfVisible: game.gfGroup.visible
		};
	}

	function restoreState(s:Dynamic):Void
	{
		game.defaultCamZoom = s.zoom;
		game.cameraSpeed = s.speed;
		game.isPixelStage = s.pixel;
		game.boyfriendCameraOffset = s.bfCam;
		game.opponentCameraOffset = s.dadCam;
		game.girlfriendCameraOffset = s.gfCam;
		game.boyfriendGroup.setPosition(s.bfX, s.bfY);
		game.dadGroup.setPosition(s.dadX, s.dadY);
		game.gfGroup.setPosition(s.gfX, s.gfY);
		game.gfGroup.visible = s.gfVisible;
	}

	// ------------------------------------------------------------------
	// Utility
	// ------------------------------------------------------------------
	function snapshot():ObjectMap<FlxBasic, Bool>
	{
		var m = new ObjectMap<FlxBasic, Bool>();
		for (o in game.members)
			if (o != null) m.set(o, true);
		return m;
	}

	function newSince(before:ObjectMap<FlxBasic, Bool>):Array<FlxBasic>
	{
		var r:Array<FlxBasic> = [];
		for (o in game.members)
			if (o != null && !before.exists(o)) r.push(o);
		return r;
	}

	function onGameCamera(o:FlxBasic):Bool
	{
		var c = o.cameras;
		return c == null || c.length == 0 || c.indexOf(game.camGame) != -1;
	}

	function parseFlags(str:String):Map<String, Bool>
	{
		var flags = new Map<String, Bool>();
		if (str == null) return flags;
		for (f in str.split(','))
		{
			f = StringTools.trim(f).toLowerCase();
			if (f != '') flags.set(f, true);
		}
		return flags;
	}

	static inline function num(v:Dynamic, def:Float = 0):Float
	{
		if (v == null) return def;
		var f = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? def : f;
	}

	function callIfExists(obj:Dynamic, fn:String, args:Array<Dynamic>):Void
	{
		try
		{
			var f = Reflect.field(obj, fn);
			if (f != null) Reflect.callMethod(obj, f, args);
		}
		catch (e:Dynamic)
		{
			trace('[Change Stage] errore in ' + fn + ': ' + e);
		}
	}

	function warn(msg:String):Void
	{
		trace('[Change Stage] ' + msg);
		#if LUA_ALLOWED
		game.addTextToDebug('[Change Stage] ' + msg, FlxColor.YELLOW);
		#end
	}
}
