package backend;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;
import haxe.ds.ObjectMap;
import sys.FileSystem;
import sys.io.File;

import backend.StageData;
import states.PlayState;

/**
 * Change Stage (porting Haxe della versione Lua "Change Stage v2 by Atox").
 *
 * Gli stage built-in (stage, spooky, philly, limo, mall, mallEvil)
 * vengono ricreati come semplici FlxSprite, MAI istanziando le classi
 * states.stages.*. Questo evita il crash "null reference" in Limo.update().
 *
 * Evento chart:
 *   Event "Change Stage"
 *     Value 1: nome stage (es. "spooky", "limo", "myCustomStage")
 *     Value 2: flag opzionali separati da virgola
 *              noblack | nochars | nozoom | nocam | nogf
 */
private typedef SpriteDef = {
	var image:String;
	var x:Float;
	var y:Float;
	@:optional var scroll:Float;
	@:optional var scrollX:Float;
	@:optional var scrollY:Float;
	@:optional var scale:Float;
	@:optional var flipX:Bool;
	@:optional var anim:String;
	@:optional var fps:Int;
	@:optional var loop:Bool;
	@:optional var beat:Bool;
	@:optional var behindDad:Bool;
	@:optional var front:Bool;
}

private class StageSlot
{
	public var name:String;
	public var members:Array<FlxBasic> = [];
	public var stages:Array<Dynamic> = [];
	public var beatSprites:Array<FlxSprite> = [];
	#if LUA_ALLOWED
	public var luas:Array<Dynamic> = [];
	#end
	#if HSCRIPT_ALLOWED
	public var hscripts:Array<Dynamic> = [];
	#end

	public function new(name:String)
	{
		this.name = name;
	}

	public function isEmpty():Bool
	{
		var empty = members.length == 0 && stages.length == 0;
		#if LUA_ALLOWED empty = empty && luas.length == 0; #end
		#if HSCRIPT_ALLOWED empty = empty && hscripts.length == 0; #end
		return empty;
	}
}

class StageChanger
{
	static var BUILTIN:Map<String, Array<SpriteDef>> = [
		'stage' => [
			{ image: 'stageback',     x: -600, y: -200, scroll: 0.9 },
			{ image: 'stagefront',    x: -650, y: 600,  scroll: 0.9, scale: 1.1 },
			{ image: 'stage_light',   x: -125, y: -100, scroll: 0.9, scale: 1.1 },
			{ image: 'stage_light',   x: 1225, y: -100, scroll: 0.9, scale: 1.1, flipX: true },
			{ image: 'stagecurtains', x: -500, y: -300, scroll: 1.3, scale: 0.9 },
		],
		'spooky' => [
			{ image: 'halloween_bg', x: -200, y: -100, anim: 'halloweem bg0' },
		],
		'philly' => [
			{ image: 'philly/sky',         x: -100, y: 0, scroll: 0.1 },
			{ image: 'philly/city',        x: -10,  y: 0, scroll: 0.3, scale: 0.85 },
			{ image: 'philly/behindTrain', x: -40,  y: 50 },
			{ image: 'philly/street',      x: -40,  y: 50 },
		],
		'limo' => [
			{ image: 'limo/limoSunset', x: -120, y: -50, scroll: 0.1 },
			{ image: 'limo/bgLimo',     x: -150, y: 480, scroll: 0.4, anim: 'background limo pink', loop: true },
			{ image: 'limo/limoDrive',  x: -120, y: 550, anim: 'Limo stage', loop: true, behindDad: true },
		],
		'mall' => [
			{ image: 'christmas/bgWalls',       x: -1000, y: -500, scroll: 0.2,  scale: 0.8 },
			{ image: 'christmas/upperBop',      x: -240,  y: -90,  scroll: 0.33, scale: 0.85, anim: 'Upper Crowd Bob', beat: true },
			{ image: 'christmas/bgEscalator',   x: -1100, y: -600, scroll: 0.3,  scale: 0.9 },
			{ image: 'christmas/christmasTree', x: 370,   y: -250, scroll: 0.4 },
			{ image: 'christmas/bottomBop',     x: -300,  y: 140,  scroll: 0.9,  anim: 'Bottom Level Boppers Idle', beat: true },
			{ image: 'christmas/fgSnow',        x: -600,  y: 700 },
			{ image: 'christmas/santa',         x: -840,  y: 150,  anim: 'santa idle in fear', beat: true },
		],
		'mallEvil' => [
			{ image: 'christmas/evilBG',   x: -400, y: -500, scroll: 0.2, scale: 0.8 },
			{ image: 'christmas/evilTree', x: 300,  y: -300, scroll: 0.2 },
			{ image: 'christmas/evilSnow', x: -200, y: 700 },
		],
	];

	var game:PlayState;
	var slots:Map<String, StageSlot> = new Map();
	var queued:Array<String> = [];

	public var current(default, null):String = '';

	var lastBeat:Int = -1;
	var hookInstalled:Bool = false;

	public function new(game:PlayState)
	{
		this.game = game;
	}

	// ==================================================================
	// API PUBBLICA
	// ==================================================================

	public function queue(name:String):Void
	{
		name = StringTools.trim(name == null ? '' : name);
		if (name == '' || name == current) return;
		if (queued.indexOf(name) == -1)
			queued.push(name);
	}

	public function captureInitial():Void
	{
		if (current != '') return;
		current = PlayState.curStage;

		var slot = new StageSlot(current);
		var bfIdx = game.members.indexOf(game.boyfriendGroup);

		for (i in 0...game.members.length)
		{
			var o = game.members[i];
			if (o == null || !o.exists) continue;
			if (isEngineObject(o)) continue;
			if (!onGameCamera(o)) continue;

			var inFront = bfIdx >= 0 && i > bfIdx;
			if (inFront && (!Std.isOfType(o, FlxSprite) || Std.isOfType(o, FlxSpriteGroup))) continue;

			slot.members.push(o);
		}

		slot.stages = game.stages.copy();

		#if LUA_ALLOWED
		for (l in game.luaArray)
			if (l.scriptName != null && l.scriptName.indexOf('stages/' + current + '.lua') != -1)
				slot.luas.push(l);
		#end
		#if HSCRIPT_ALLOWED
		for (h in game.hscriptArray)
			if (h.origin != null && h.origin.indexOf('stages/' + current + '.hx') != -1)
				slot.hscripts.push(h);
		#end

		slots.set(current, slot);
		installBeatHook();
	}

	public function preloadQueued():Void
	{
		for (n in queued)
		{
			if (n == current) continue;
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

	public function change(name:String, ?flagsStr:String = ''):Void
	{
		name = StringTools.trim(name == null ? '' : name);
		if (name == '') return;

		if (current == '') captureInitial();
		if (name == current) return;

		var flags = parseFlags(flagsStr);

		var prev = slots.get(current);
		if (prev != null) setSlot(prev, false);

		var next = slots.get(name);
		if (next == null)
		{
			next = build(name);
			if (next == null)
			{
				warn('stage "' + name + '" not found (no builtin, no .lua/.hx, no objects).');
				return;
			}
			slots.set(name, next);
		}

		setSlot(next, true);
		current = name;

		applyStageData(StageData.getStageFile(name), flags);

		game.moveCameraSection();
	}

	public function destroy():Void
	{
		if (hookInstalled)
		{
			FlxG.signals.postUpdate.remove(beatHook);
			hookInstalled = false;
		}

		#if LUA_ALLOWED
		for (s in slots)
			for (l in s.luas)
				if (game.luaArray.indexOf(l) == -1)
					l.stop();
		#end

		slots.clear();
	}

	// ==================================================================
	// COSTRUZIONE STAGE
	// ==================================================================
	function build(name:String):StageSlot
	{
		if (name == current || slots.exists(name)) return null;

		var slot = new StageSlot(name);
		var before = snapshot();

		// 1) stage built-in: ricrea come sprite (come fa il Lua)
		if (BUILTIN.exists(name))
			buildBuiltin(name, slot, false);

		// 2) oggetti json del stage
		var sd:Dynamic = StageData.getStageFile(name);
		var objs:Array<Dynamic> = (sd != null) ? sd.objects : null;
		if (objs != null && objs.length > 0)
		{
			try
			{
				var hideGf:Bool = (sd.hide_girlfriend == true);
				var list:Map<String, FlxSprite> = StageData.addObjectsToState(objs,
					hideGf ? null : game.gfGroup, game.dadGroup, game.boyfriendGroup, game);
				for (key => spr in list)
					if (!StageData.reservedNames.contains(key))
						game.variables.set(key, spr);
			}
			catch (e:Dynamic)
			{
				warn('error creating objects for "' + name + '": ' + e);
			}
		}

		// 3) script dello stage (.lua / .hx)
		#if LUA_ALLOWED
		var luaBefore = game.luaArray.length;
		game.startLuasNamed('stages/' + name + '.lua');
		#end
		#if HSCRIPT_ALLOWED
		var hBefore = game.hscriptArray.length;
		game.startHScriptsNamed('stages/' + name + '.hx');
		#end

		// 4) onCreatePost sugli script appena creati
		#if LUA_ALLOWED
		for (i in luaBefore...game.luaArray.length)
		{
			var l = game.luaArray[i];
			slot.luas.push(l);
			try l.call('onCreatePost', []) catch (e:Dynamic) {};
		}
		#end
		#if HSCRIPT_ALLOWED
		for (i in hBefore...game.hscriptArray.length)
		{
			var h = game.hscriptArray[i];
			slot.hscripts.push(h);
			if (h.exists('onCreatePost'))
			{
				try h.call('onCreatePost') catch (e:Dynamic) {};
			}
		}
		#end

		// 5) raccogli i nuovi membri
		for (o in newSince(before))
			if (o != null && o.exists) slot.members.push(o);

		// 6) sposta gli sprite appena aggiunti dietro ai personaggi
		for (o in slot.members)
			insertBehindChars(o);

		if (slot.isEmpty()) return null;
		return slot;
	}

	function buildBuiltin(name:String, slot:StageSlot, visible:Bool):Void
{
    var defs = BUILTIN.get(name);
    if (defs == null) return;

    // ---- Legge il JSON con lo stesso metodo del Lua ----
    var dir:String = '';
    var rawText:String = Paths.getTextFromFile('stages/' + name + '.json');
    if (rawText != null && rawText.length > 0)
    {
        try
        {
            var raw:Dynamic = haxe.Json.parse(rawText);
            if (raw != null && raw.directory != null)
                dir = Std.string(raw.directory);
        }
        catch (e:Dynamic)
        {
            trace('[ChangeStage] json parse error: ' + e);
        }
    }
    else
    {
        trace('[ChangeStage] json NOT FOUND: stages/' + name + '.json');
    }

    // ---- Salva currentLevel attuale ----
    var prevLevel:Dynamic = null;
    try prevLevel = Reflect.field(Paths, 'currentLevel') catch (e:Dynamic) {};

    // ---- Applica la nuova directory (doppia strategia) ----
    if (dir.length > 0)
    {
        try Reflect.setProperty(Paths, 'currentLevel', dir)
        catch (e:Dynamic) trace('[ChangeStage] setProperty failed: ' + e);
        try Reflect.setField(Paths, 'currentLevel', dir)
        catch (e:Dynamic) trace('[ChangeStage] setField failed: ' + e);
    }

    trace('[ChangeStage] stage=$name dir=$dir prev=$prevLevel now=' + Std.string(Reflect.field(Paths, 'currentLevel')));
    // ----------------------------------------------------

    for (i in 0...defs.length)
    {
        var d = defs[i];
        var spr:FlxSprite = new FlxSprite(d.x, d.y);
        spr.antialiasing = ClientPrefs.data.antialiasing;

        // *** PULISCI LA CACHE prima di ricaricare ***
        // Se l'immagine è già cachata (magari come placeholder), rimuovila
        try FlxG.bitmap.removeByKey(d.image) catch (e:Dynamic) {};

        var animFps:Int = (d.fps != null) ? d.fps : 24;
        var doLoop:Bool = (d.loop == true);

        if (d.anim != null)
        {
            spr.frames = Paths.getSparrowAtlas(d.image);
            spr.animation.addByPrefix('idle', d.anim, animFps, doLoop);
            spr.animation.play('idle', true);
        }
        else
        {
            spr.loadGraphic(Paths.image(d.image));
        }

        var sx:Float = (d.scrollX != null) ? d.scrollX : ((d.scroll != null) ? d.scroll : 1);
        var sy:Float = (d.scrollY != null) ? d.scrollY : ((d.scroll != null) ? d.scroll : 1);
        spr.scrollFactor.set(sx, sy);

        if (d.scale != null) spr.scale.set(d.scale, d.scale);
        if (d.flipX == true) spr.flipX = true;

        spr.updateHitbox();
        spr.visible = true;
        spr.exists = visible;
        spr.active = visible;

        game.add(spr);
        slot.members.push(spr);
        if (d.beat == true) slot.beatSprites.push(spr);

        insertBehindChars(spr);

        if (d.behindDad == true && game.dadGroup != null)
        {
            var dadIdx = game.members.indexOf(game.dadGroup);
            if (dadIdx >= 0)
            {
                game.remove(spr, true);
                game.insert(dadIdx, spr);
            }
        }
    }

    // ---- Ripristina currentLevel ----
    if (prevLevel != null)
    {
        try Reflect.setProperty(Paths, 'currentLevel', prevLevel) catch (e:Dynamic) {};
        try Reflect.setField(Paths, 'currentLevel', prevLevel) catch (e:Dynamic) {};
    }
}

	// ==================================================================
	// SHOW / HIDE
	// ==================================================================
	function setSlot(s:StageSlot, on:Bool):Void
	{
		for (o in s.members)
		{
			if (o == null) continue;
			o.exists = on;
			o.active = on;
			if (Std.isOfType(o, FlxSprite))
				(cast o : FlxSprite).visible = on;
		}

		for (st in s.stages)
		{
			if (st == null) continue;
			Reflect.setProperty(st, 'exists', on);
			Reflect.setProperty(st, 'active', on);
		}

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

	// ==================================================================
	// DATI STAGE DAL JSON
	// ==================================================================
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

		if (!flags.exists('nogf') && sd.hide_girlfriend != null)
			game.gfGroup.visible = !(sd.hide_girlfriend == true);

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

	// ==================================================================
	// BEAT HOOK (per animazioni beat-synced tipo mall)
	// ==================================================================
	function installBeatHook():Void
	{
		if (hookInstalled) return;
		hookInstalled = true;
		FlxG.signals.postUpdate.add(beatHook);
	}

	function beatHook():Void
	{
		if (game == null) return;
		var cb:Int = game.curBeat;
		if (cb == lastBeat) return;
		lastBeat = cb;
		onBeat();
	}

	function onBeat():Void
	{
		var slot = slots.get(current);
		if (slot == null) return;
		for (spr in slot.beatSprites)
		{
			if (spr != null && spr.exists && spr.animation != null && spr.animation.exists('idle'))
				spr.animation.play('idle', true);
		}
	}

	// ==================================================================
	// UTILITY
	// ==================================================================
	function insertBehindChars(spr:FlxBasic):Void
	{
		if (spr == null) return;
		var ref:FlxBasic = game.gfGroup != null ? game.gfGroup : game.boyfriendGroup;
		if (ref == null) return;

		var refIdx = game.members.indexOf(ref);
		if (refIdx < 0) return;

		var curIdx = game.members.indexOf(spr);
		if (curIdx < 0 || curIdx < refIdx) return;

		game.remove(spr, true);
		game.insert(refIdx, spr);
	}

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

	function isEngineObject(o:FlxBasic):Bool
	{
		return o == game.gfGroup || o == game.dadGroup || o == game.boyfriendGroup
			|| o == game.comboGroup || o == game.uiGroup || o == game.noteGroup
			|| o == game.camFollow;
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

	function warn(msg:String):Void
	{
		trace('[Change Stage] ' + msg);
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		game.addTextToDebug('[Change Stage] ' + msg, FlxColor.YELLOW);
		#end
	}
}
