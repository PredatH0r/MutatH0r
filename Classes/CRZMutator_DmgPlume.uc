class CRZMutator_DmgPlume extends CRZMutator config (MutatH0r);

// structures sent from server to clients

struct PlumeRepItem
{
  var vector Location;
  var int Value;
};

struct PlumeRepInfo
{
  var PlumeRepItem Plumes[16];
};

// server internal structures to aggregate damage within one tick for each client and victim

struct PlumeVictimInfo
{
  var Pawn Victim;
  var PlumeRepItem RepItem;
};

struct PlumeReceiver
{
  var Controller Controller;
  var DmgPlumeActor Actor;
  var array<PlumeVictimInfo> Victims;
};


// server
var config string forceKillSound;
var array<PlumeReceiver> PlumeReceivers;


function PostBeginPlay()
{
  super.PostBeginPlay();

  if (Role == ROLE_Authority)
  {
    SetTickGroup(TG_PostAsyncWork);
    Enable('Tick');
  }
}

function InitMutator(string options, out string errorMsg)
{
  super.InitMutator(options, errorMsg);
  MoveMyselfToHeadOfMutatorList();
}

function MoveMyselfToHeadOfMutatorList()
{
  // move this mutator to the start of the mutator list so we don't miss any NetDamage() modifications

  local Mutator mut;
 
  if (WorldInfo.Game.BaseMutator == self)
    return;
  for (mut = WorldInfo.Game.BaseMutator; mut != None; mut=mut.NextMutator)
  {
    if (mut.NextMutator == self)
    {
      mut.NextMutator = self.NextMutator;
      self.NextMutator = WorldInfo.Game.BaseMutator;
      WorldInfo.Game.BaseMutator = self;
      return;
    }
  }
}

function NetDamage(int OriginalDamage, out int Damage, Pawn Injured, Controller InstigatedBy, Vector HitLocation, out Vector Momentum, class<DamageType> DamageType, Actor DamageCauser)
{
  local int i, j;
  local CRZPlayerController pc;
  
  super.NetDamage(OriginalDamage, Damage, Injured, InstigatedBy, HitLocation, Momentum, DamageType, DamageCauser);

  foreach WorldInfo.AllControllers(class'CRZPlayerController', PC)
  {
    if (!HasPovOfAttacker(PC, InstigatedBy))
      continue;

    i = GetOrAddPlumeReceiver(pc);

    // find or create plume for victim and aggregate damage
    for (j=0; j<PlumeReceivers[i].Victims.Length; j++)
    {
      if (PlumeReceivers[i].Victims[j].Victim == Injured)
        break;
    }
    if (j>=PlumeReceivers[i].Victims.Length)
    {
      PlumeReceivers[i].Victims.Add(1);
      PlumeReceivers[i].Victims[j].Victim = Injured;
      PlumeReceivers[i].Victims[j].RepItem.Location = Injured.Location + vect(0,0,1)*(Injured.CylinderComponent.CollisionHeight + 3);
    }
    PlumeReceivers[i].Victims[j].RepItem.Value += pc.Pawn == None ? Damage : round(Damage * pc.Pawn.DamageScaling); // attacker may have died before his projectile deals damage
  }
}

function bool HasPovOfAttacker(CRZPlayerController player, Controller attacker)
{
  return player.RealViewTarget == none ? (player == attacker) : (player.RealViewTarget == attacker.PlayerReplicationInfo);
}

function Tick(float deltaTime)
{
  local int i, j;
  local PlumeReceiver rec;
  local PlumeRepInfo repInfo;

  if (Role != ROLE_Authority)
    return;

  for (i=0; i<PlumeReceivers.Length; i++)
  {
    rec = PlumeReceivers[i];
    if (rec.Victims.Length == 0)
      continue;
    
    for (j=0; j<rec.Victims.Length && j<ArrayCount(repInfo.Plumes); j++)
      repInfo.Plumes[j] = rec.Victims[j].RepItem;
    if (j < ArrayCount(repInfo.Plumes)) // mark as end-of-list
      repInfo.Plumes[j].Value = 0;
    rec.Actor.AddPlumes(repInfo);
    PlumeReceivers[i].Victims.Length = 0; // must use full path to set original struct member and not the local copy
  }
}

function int GetOrAddPlumeReceiver(Controller C)
{
  local int i;

  // find or create plume receiver
  for (i=0; i<PlumeReceivers.Length; i++)
  {
    if (PlumeReceivers[i].Controller == C)
      return i;
  }

  PlumeReceivers.Add(1);
  PlumeReceivers[i].Controller = C;
  PlumeReceivers[i].Actor = Spawn(class'DmgPlumeActor', C);
  PlumeReceivers[i].Actor.Mut = self;
  return i;
}

function NotifyLogin(Controller C)
{
  local int i;
  super.NotifyLogin(C);

  if (PlayerController(C) != None)
  {
    i = GetOrAddPlumeReceiver(C);
    if (i>=0 && forceKillSound != "")
      PlumeReceivers[i].Actor.SetKillSound(forceKillSound);
  }
}

function NotifyLogout(Controller C)
{
  local int i, j, playerId;

  if (PlayerController(C) != None)
  {
    for (i=0; i<PlumeReceivers.Length; i++)
    {
      if (PlumeReceivers[i].Controller == C)
      { 
        // tell all clients that the player isn't typing anymore (he may reconnect later, and should not have a chat bubble)
        if (PlumeReceivers[i].Actor.isTyping)
        {
          playerId = C.PlayerReplicationInfo.PlayerID;
          for (j=0; j<PlumeReceivers.Length; j++)
          {
            if (PlumeReceivers[j].Controller != C)
              PlumeReceivers[j].Actor.NotifyIsTyping(playerId, false);
          }
        }

        PlumeReceivers[i].Actor.Destroy();
        PlumeReceivers.Remove(i, 1);
        break;
      }
    }
  }

  super.NotifyLogout(C);
}

function ScoreKill (Controller killer, Controller killed)
{
  local int i;
  local CRZPlayerController pc;

  super.ScoreKill(killer, killed);

  if (killer == none || killer == killed)
    return;

  foreach WorldInfo.AllControllers(class'CRZPlayerController', PC)
  {
    if (!HasPovOfAttacker(pc, killer))
      continue;
    i = GetOrAddPlumeReceiver(pc);
    PlumeReceivers[i].Actor.PlayKillSound();
  }
}

function SetForceKillSound(string soundId)
{
  local int i;
  forceKillSound = soundId;
  for (i=0; i<plumeReceivers.Length; i++)
    PlumeReceivers[i].Actor.SetKillSound(soundId, false);
}

function Mutate(string MutateString, PlayerController sender)
{
  if (instr(locs(MutateString), "forcekillsound") == 0)
    SetForceKillsound(mid(MutateString, 15));
  else
    super.Mutate(MutateString, sender);
}

static function PopulateConfigView(GFxCRZFrontEnd_ModularView ConfigView, optional CRZUIDataProvider_Mutator MutatorDataProvider)
{
  local GFxObject TempObj;
  local GFxObject DataProviderPlumes, DataProviderKillSounds;
  local int i,j;
  local array<string> presetNames;
  local string presetName;
  local int presetIndex, killSoundIndex;

  super.PopulateConfigView(ConfigView, MutatorDataProvider);
  
  if (!GetPerObjectConfigSections(class'DmgPlumeConfig', presetNames)) // names are returned in reverse order
  {
    presetNames.AddItem("huge");
    presetNames.AddItem("large");
    presetNames.AddItem("small");
  }
  presetNames.AddItem("off");

  DataProviderPlumes = ConfigView.outer.CreateArray();
  j=0;
  for(i=presetNames.Length-1; i>=0; i--)
  {
    presetName = repl(locs(presetNames[i]), " dmgplumeconfig", "");

    TempObj = ConfigView.MenuManager.CreateObject("Object");
    TempObj.SetString("label", presetName);
    DataProviderPlumes.SetElementObject(j, TempObj);

    if (presetName == class'DmgPlumeActor'.default.DmgPlumeConfig)
      presetIndex = j;
    ++j;
  }

  DataProviderKillSounds = ConfigView.outer.CreateArray();
  for(i=0; i<class'DmgPlumeActor'.default.KillSounds.Length; i++)
  {
    TempObj = ConfigView.MenuManager.CreateObject("Object");
    TempObj.SetString("label", class'DmgPlumeActor'.default.KillSounds[i].Label);
    DataProviderKillSounds.SetElementObject(i, TempObj);

    if (class'DmgPlumeActor'.default.KillSounds[i].Label == class'DmgPlumeActor'.default.KillSound)
      killSoundIndex = i;
  }

  ConfigView.SetMaskBounds(ConfigView.ListObject1, 400, 975, true);
  class'MutConfigHelper'.static.NotifyPopulated(class'CRZMutator_DmgPlume');
  class'MutConfigHelper'.static.AddSlider(ConfigView, "Damage Numbers", "Size and appearance of damage numbers", 0, presetNames.Length - 1, 1, presetIndex, static.OnSliderChanged, DataProviderPlumes);
  class'MutConfigHelper'.static.AddSlider(ConfigView, "Kill Sound", "Sound played when you kill a player", 0, class'DmgPlumeActor'.default.KillSounds.Length - 1, 1, killSoundIndex, static.OnSliderChanged, DataProviderKillSounds);
  class'MutConfigHelper'.static.AddSlider(ConfigView, "Kill Sound Vol", "Kill sound volume", 0, 400, 5, int(class'DmgPlumeActor'.default.KillSoundVolume * 100), static.OnSliderChanged);
}

function static OnSliderChanged(string label, float value, GFxClikWidget.EventData ev)
{
  local GFxObject DataProvider;
  local string presetName;
  local SoundCue cue;

  DataProvider = ev.target.GetObject("dataProvider");
  presetName = DataProvider == none ? "" : DataProvider.GetElementObject(int(value)).GetString("label");

  if (label == "Damage Numbers")
    class'DmgPlumeActor'.default.DmgPlumeConfig = presetName;
  else if (label == "Kill Sound")
  {
    class'DmgPlumeActor'.default.KillSound = presetName;
    cue = class'DmgPlumeActor'.static.GetKillSound(presetName);
    if (cue != none)
      class'WorldInfo'.static.GetWorldInfo().GetALocalPlayerController().ClientPlaySound(cue);
  }
  else if (label == "Kill Sound Vol")
    class'DmgPlumeActor'.default.KillSoundVolume = value/100;

  class'DmgPlumeActor'.static.StaticSaveConfig();
}

defaultproperties
{
}