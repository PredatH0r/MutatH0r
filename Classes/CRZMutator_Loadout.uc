class CRZMutator_Loadout extends UTMutator config(MutatH0r);

const OPT_LoadoutPreset = "?LoadoutPreset=";
const OPT_Loadout = "?Loadout=";

var CRZMUtator_LoadoutPreset preset;
var array<class<Weapon> > weapons;
var bool InfiniteAmmo;

replication
{
  if (Role == ROLE_Authority && (bNetInitial || bNetDirty))
    InfiniteAmmo;
}

function PostBeginPlay()
{
  Super.PostBeginPlay();

  // UTInvManager.bInfiniteAmmo only resets the ammo count back to MaxValue when it goes below 0, which prevents shots that need more than 1 ammo
  // Without the SDKK and the ability to subclass the weapons, the only way to modify them on the client side is through Tick
  SetTickGroup(ETickingGroup.TG_DuringAsyncWork);
  Enable('Tick');
}

function InitMutator(string options, out string error)
{
  local int idx;
  local string s, presetId;
  
  super.InitMutator(options, error);

  // extract preset number from ?LoadoutPreset=... parameter
  idx = instr(options, OPT_LoadoutPreset, false, true);
  if (idx >= 0)
  {
    s = mid(options, idx + len(OPT_LoadoutPreset));
    idx = instr(s, "?");
    if (idx >= 0)
      s = left(s, idx);
    presetId = s;
  }
  if (presetId == "")
    presetId = "Preset1";

  // load the preset and initialize internal variables
  preset = new(none, presetId) class'CRZMutator_LoadoutPreset';
  ApplyOptionOverrides(options);
  InitWeapons();
  if (weapons.Length == 0)
  {
    // failsafe for bad config or preset name
    preset = new() class'CRZMutator_LoadoutPreset';
    preset.Ravager = true;
    preset.Raven = true;
    preset.AllowWeaponPickups = true;
    InitWeapons();
  }

  InfiniteAmmo = preset.InfiniteAmmo;
  if (!preset.RandomWeapon)
    SetDefaultInventory();
}

function ApplyOptionOverrides(string options)
{
  local int idx;
  local string s;
  
  // extract ?Loadout=... parameter
  idx = instr(options, OPT_Loadout, false, true);
  if (idx < 0) 
    return;
  
  s = mid(options, idx + len(OPT_Loadout));
  idx = instr(s, "?");
  if (idx >= 0)
    s = left(s, idx);
  `log("Loadout=" $ s);
  if (s == "")
    return;

  preset.Ravager = instr(s, "1") >= 0;
  preset.Raven = instr(s, "2") >= 0;
  preset.Bullcraft = instr(s, "3") >= 0;
  preset.Violator = instr(s, "4") >= 0;
  preset.Falcon = instr(s, "5") >= 0;
  preset.Stingray = instr(s, "6") >= 0;
  preset.Dragoneer = instr(s, "7") >= 0;
  preset.Cerberus = instr(s, "8") >= 0;
  preset.AllowWeaponPickups = instr(s, "P", false, true) >= 0;
  preset.InfiniteAmmo = instr(s, "A", false, true) >= 0;
  preset.RandomWeapon = instr(s, "R", false, true) >= 0;
}

function InitWeapons()
{
  if (preset.Ravager)
    weapons.AddItem(class<Weapon>(DynamicLoadObject("Cruzade.CRZWeap_Impactor", class'Class')));
  if (preset.Raven)
    weapons.AddItem(class<Weapon>(DynamicLoadObject("Cruzade.CRZWeap_PistolAW29", class'Class')));
  if (preset.Bullcraft)
    weapons.AddItem(class<Weapon>(DynamicLoadObject("Cruzade.CRZWeap_ShotgunSG12", class'Class')));
  if (preset.Violator)
    weapons.AddItem(class<Weapon>(DynamicLoadObject("Cruzade.CRZWeap_PulseRifle", class'Class')));
  if (preset.Falcon)
    weapons.AddItem(class<Weapon>(DynamicLoadObject("Cruzade.CRZWeap_SniperRifle", class'Class')));
  if (preset.Stingray)
    weapons.AddItem(class<Weapon>(DynamicLoadObject("Cruzade.CRZWeap_ScionRifle", class'Class')));
  if (preset.Dragoneer)
    weapons.AddItem(class<Weapon>(DynamicLoadObject("Cruzade.CRZWeap_FlameThrower", class'Class')));
  if (preset.Cerberus)
    weapons.AddItem(class<Weapon>(DynamicLoadObject("Cruzade.CRZWeap_RocketLauncher", class'Class')));
}

function SetDefaultInventory()
{
  local UTGame Game;
  local int i;

  Game = UTGame(WorldInfo.Game);
  if (Game == None) return;

  Game.DefaultInventory.Length = 0;

  if (preset.RandomWeapon)
    Game.DefaultInventory.AddItem(weapons[rand(weapons.Length)]);
  else
  {
    for (i=0; i<weapons.Length; i++)
      Game.DefaultInventory.AddItem(weapons[i]);  
  }
}

function bool CheckReplacement(Actor Other)
{
  local UTPawn pawn;

  // toxikk doesn't derive from UTAmmoPickupFactory, so check for it the dirty way
  if (InfiniteAmmo && Other.IsA('UTItemPickupFactory') && instr(string(Other.class), "CRZAmmo_") == 0)
    return false;

  if (!preset.AllowWeaponPickups && (Other.IsA('UTWeaponPickupFactory') || Other.IsA('UTWeaponLocker')))
    return false;

  if (preset.RandomWeapon)
  {
    pawn = UTPawn(Other);
    if (pawn != None)
      SetDefaultInventory();
  }

  return super.CheckReplacement(Other);
}

simulated function Tick(float DeltaTime)
{
  local UTWeapon w;

  if (InfiniteAmmo)
  {
    foreach WorldInfo.DynamicActors(class'UTWeapon', w)
    {
      w.ShotCost[0] = 0;
      w.ShotCost[1] = 0;
    }
  }
}

defaultproperties
{
  RemoteRole=ROLE_SimulatedProxy
  bAlwaysRelevant=true
  GroupNames[0]="WEAPONMOD"
  GroupNames[1]="WEAPONRESPAWN"
}
