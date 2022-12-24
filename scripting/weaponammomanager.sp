#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#pragma semicolon 1

int g_EntRef[MAXPLAYERS + 1];
int g_CurrAmmo[MAXPLAYERS + 1];
int g_ReserveAmmo[MAXPLAYERS + 1];
int g_Check[MAXPLAYERS + 1];

KeyValues kv;

ArrayList g_ClassNames;
ArrayList g_ClipSizes;
ArrayList g_ReserveSizes;

public void OnPluginStart() {
	g_ClassNames = new ArrayList(ByteCountToCells(64));
	g_ClipSizes = new ArrayList(ByteCountToCells(8));
	g_ReserveSizes = new ArrayList(ByteCountToCells(8));
	
	LoadKV();
	
	for(int i = 1; i <= MaxClients; i++)
		if(IsClientConnected(i) && IsClientInGame(i))
			OnClientPutInServer(i);
}

public void OnPluginEnd() {
	for(int i = 1; i <= MaxClients; i++)
		if(IsClientConnected(i) && IsClientInGame(i))
			OnClientDisconnect(i);
}

public void OnClientPutInServer(int client) {
	g_EntRef[client] = -1;
	g_CurrAmmo[client] = -1;
	g_ReserveAmmo[client] = -1;
	g_Check[client] = 0;
	
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
}

public void OnClientDisconnect(int client) {
	SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
}

// Set Ammo at spawn
public void OnWeaponEquipPost(int client, int weapon) {
	if(!IsValidClient(client) || !IsValidEdict(weapon))
		return;
		

	CreateTimer(0.0, TimerWeaponSpawn, GetClientSerial(client));
}

public Action TimerWeaponSpawn(Handle timer, int serial) {
	int client = GetClientFromSerial(serial);
	if(!IsValidClient(client))
		return Plugin_Stop;

	
	int weapon = GetPlayerWeaponSlot(client, 0);
	if(!IsValidEdict(weapon))
		return Plugin_Stop;

	char classname[64];
	char compareclass[64];
	GetEntityClassname(weapon, classname, sizeof(classname));

	int index = -1;
	for (int i = 0; i < GetArraySize(g_ClassNames); i++) {
		GetArrayString(g_ClassNames, i, compareclass, sizeof(compareclass));
		if (StrEqual(classname, compareclass))
			index = i;
	}

	if(index <= -1)
		return Plugin_Stop;
	
	int clipsize = g_ClipSizes.Get(index);
	int reservesize = g_ReserveSizes.Get(index);
	
	if(clipsize >= 0)
		SetEntProp(weapon, Prop_Data, "m_iClip1", clipsize);

	if(reservesize >= 0) {
		SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", reservesize);
		SetEntProp(weapon, Prop_Send, "m_iSecondaryReserveAmmoCount", reservesize);	
	}
	
	// I know this method is shitty
	index = -1;
	int weapon2 = GetPlayerWeaponSlot(client, 1);
	if(!IsValidEdict(weapon2))
		return Plugin_Stop;

	for (int i = 0; i < GetArraySize(g_ClassNames); i++) {
		GetArrayString(g_ClassNames, i, compareclass, sizeof(compareclass));
		if (StrEqual(classname, compareclass))
			index = i;
	}

	if(index <= -1)
		return Plugin_Stop;
	
	clipsize = g_ClipSizes.Get(index);
	reservesize = g_ReserveSizes.Get(index);
	
	if(GetEntProp(weapon, Prop_Data, "m_iClip1") != clipsize || GetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", reservesize) != reservesize || GetEntProp(weapon, Prop_Send, "m_iSecondaryReserveAmmoCount", reservesize) != reservesize)
		return Plugin_Stop;
	
	if(clipsize >= 0)
		SetEntProp(weapon, Prop_Data, "m_iClip1", clipsize);

	if(reservesize >= 0) {
		SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", reservesize);
		SetEntProp(weapon, Prop_Send, "m_iSecondaryReserveAmmoCount", reservesize);	
	}

	return Plugin_Stop;
}

// Set Ammo After Reload
public void OnEntityCreated(int entity, const char[] classname) {
	if(!IsValidEdict(entity))
		return;
		
	if(StrContains(classname, "weapon_", true) != -1) {
		char compareclass[64];
		
		int index = -1;
		for (int i = 0; i < GetArraySize(g_ClassNames); i++) {
			GetArrayString(g_ClassNames, i, compareclass, sizeof(compareclass));
			if (StrEqual(classname, compareclass))
				index = i;
			}
	
		if(index == -1)
			return;
	
		SDKHook(entity, SDKHook_ReloadPost, OnWeaponReloadPost);
		CreateTimer(0.0, TimerWeaponSpawn, EntIndexToEntRef(entity));
	}
}

public void OnWeaponReloadPost(int entity, bool succes) {
	if (!succes)
		return;
		
	int client = GetEntPropEnt(entity, Prop_Send, "m_hOwner");
	if(!IsValidClient(client))
		return;
		
	char classname[32];
	GetEdictClassname(entity, classname, sizeof(classname));
	char compareclass[64];

	int index = -1;
	for (int i = 0; i < GetArraySize(g_ClassNames); i++) {
		GetArrayString(g_ClassNames, i, compareclass, sizeof(compareclass));
		if (StrEqual(classname, compareclass))
			index = i;
		}
	
	if(index == -1)
		return;

	g_EntRef[client] = EntIndexToEntRef(entity);
	g_CurrAmmo[client] = GetEntProp(entity, Prop_Data, "m_iClip1");
	g_ReserveAmmo[client] = GetEntProp(entity, Prop_Send, "m_iPrimaryReserveAmmoCount") - (g_ClipSizes.Get(index) - g_CurrAmmo[client]);
	g_Check[client] = 1;
	CreateTimer(0.1, OnWeaponReloadCheck, GetClientSerial(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action OnWeaponReloadCheck(Handle timer, int serial) {
	int client = GetClientFromSerial(serial);
	if(!IsValidClient(client))
		return Plugin_Stop;

	int weapon = EntRefToEntIndex(g_EntRef[client]);
	if(!IsValidEdict(weapon))
		return Plugin_Stop;
		
	int compare = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(compare != weapon)
		return Plugin_Stop;

	if(GetEntProp(weapon, Prop_Data, "m_iClip1") == g_CurrAmmo[client])
		return Plugin_Continue;

	char classname[64];
	GetEdictClassname(weapon, classname, sizeof(classname));

	char compareclass[64];
	int index = -1;
	for (int i = 0; i < GetArraySize(g_ClassNames); i++) {
		GetArrayString(g_ClassNames, i, compareclass, sizeof(compareclass));
		if (StrEqual(classname, compareclass))
			index = i;
	}

	if(index <= -1)
		return Plugin_Stop; 
	
	int clipsize = g_ClipSizes.Get(index);
	int reservesize = g_ReserveSizes.Get(index);

	if(clipsize >= 0) {
		SetEntProp(weapon, Prop_Data, "m_iClip1", clipsize);
		SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", g_ReserveAmmo[client]);
		SetEntProp(weapon, Prop_Send, "m_iSecondaryReserveAmmoCount", g_ReserveAmmo[client]);	
	}

	if(reservesize == 0) {
		SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", 500);
		SetEntProp(weapon, Prop_Send, "m_iSecondaryReserveAmmoCount", 500);	
	}
	
	if(g_Check[client] == 1) {
		g_Check[client]++;
		g_CurrAmmo[client] = clipsize;
		return Plugin_Continue;
	}
	
	g_Check[client] = 0;
	return Plugin_Stop;
}

// Load KeyValues
void LoadKV() {
	kv.Close();
	
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/empyrean/weapons.txt");
	
	kv = new KeyValues("Weapons");
	kv.ImportFromFile(path);
	
	char section[64];
	char model[16];
	
	if(kv.GotoFirstSubKey())
		do {
			kv.GetSectionName(section, sizeof(section));
			g_ClassNames.PushString(section);
			
			kv.GetString("clipsize", model, sizeof(model));
			if(!StrEqual(model, "")) {
				int x = StringToInt(model);
				if(x >= 0) g_ClipSizes.Push(x);
			} else g_ClipSizes.Push(-1);
			
			kv.GetString("reservesize", model, sizeof(model));
			if(!StrEqual(model, "")) {
				int y = StringToInt(model);
				if(y >= 0) g_ReserveSizes.Push(y);
			} else g_ReserveSizes.Push(-1);

		} while (kv.GotoNextKey());
	
	kv.Close();
}

// Some Methods
bool IsValidClient(int client) {
	if (!(1 <= client <= MaxClients) || !IsClientConnected(client) || !IsClientInGame(client)) return false;
	return true;
}