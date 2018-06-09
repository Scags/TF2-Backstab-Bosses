#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

Handle hWorldSpaceCenter;
//Handle hSendWeaponAnim;
//Handle hGetSwingRange;

ConVar cvDamage, cvDelay, bEnabled;

#define PLUGIN_VERSION 			"1.0.0"

public Plugin myinfo =
{
	name = "[TF2] Boss Backstabs",
	author = "Scag/Ragenewb",
	description = "Cower, fools! Merasmus is here!",
	version = PLUGIN_VERSION,
	url = "https://github.com/Scags/"
};

methodmap TraceRay < Handle
{
	public TraceRay( const float pos[3], const float vec[3], int flags, RayType rtype, TraceEntityFilter filter, any data=0 )
	{
		return view_as< TraceRay >(TR_TraceRayFilterEx(pos, vec, flags, rtype, filter, data));
	}
	public static TraceRay AsHull( const float pos[3], const float vec[3], const float mins[3], const float maxs[3], int flags )
	{
		return view_as< TraceRay >(TR_TraceHullEx(pos, vec, mins, maxs, flags));
	}
	public static TraceRay AsHullFilter( const float pos[3], const float vec[3], const float mins[3], const float maxs[3], int flags, TraceEntityFilter filter, any data=0 )
	{
		return view_as< TraceRay >(TR_TraceHullFilterEx(pos, vec, mins, maxs, flags, filter, data));
	}
	property float Fraction
	{
		public get()
		{
			return TR_GetFraction(this);
		}
	}
	public void GetEndPosition( float pos[3] )
	{
		TR_GetEndPosition(pos, this);
	}
	property int EntityIndex
	{
		public get()
		{
			return TR_GetEntityIndex(this);
		}
	}
	property bool DidHit
	{
		public get()
		{
			return TR_DidHit(this);
		}
	}
	property int HitGroup
	{
		public get()
		{
			return TR_GetHitGroup(this);
		}
	}
	property bool AllSolid
	{
		public get()
		{
			return this.Fraction != 0.0;
		}
	}
	public void GetPlaneNormal( float normal[3] )
	{
		TR_GetPlaneNormal(this, normal);
	}
};

public void OnPluginStart()
{
	// 150 L; 149 W
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetVirtual(149);
	PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByRef);
	if ((hWorldSpaceCenter = EndPrepSDKCall()) == null)
		SetFailState("Failed to load CBaseEntity::WorldSpaceCenter");

	// 248 L; 242 W
	/*StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetVirtual(242);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	if ((hSendWeaponAnim = EndPrepSDKCall()) == null)
		SetFailState("Failed to load CTFKnife::SendWeaponAnim");*/

	// 466 L; 459 W
	/*StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetVirtual(459);
	PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByRef);
	if ((hGetSwingRange = EndPrepSDKCall()) == null)
		SetFailState("Failed to load CTFWeaponBaseMelee::GetSwingRange");*/

	bEnabled = CreateConVar("sm_bossstab_enable", "1", "Enable the Boss Backstab plugin?", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvDamage = CreateConVar("sm_bossstab_damage", "1000", "How much damage do backstabs do?", FCVAR_NOTIFY, true, 0.0);
	cvDelay = CreateConVar("sm_bossstab_delay", "1.5", "Delay in seconds between attacks upon a successful backstab.", FCVAR_NOTIFY, true, 0.0);
	CreateConVar("sm_bossstab_version", PLUGIN_VERSION, "Boss Backstab plugin version. No touchy", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);

	RegAdminCmd("sm_hp", HP, ADMFLAG_ROOT);
}

public Action HP(int client, int args)
{
	SetEntityHealth(client, 10000);
}

public void OnMapStart()
{
	PrecacheSound("player/spy_shield_break.wav", true);
	PrecacheSound("player/crit_received3.wav", true);
}


/*public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_PreThink, OnPreThink);
}*/

public Action TF2_CalcIsAttackCritical(int client, bool &result)
{
	if (!bEnabled.BoolValue)
		return Plugin_Continue;

	if (!(0 < client < MaxClients))
		return Plugin_Continue;

	int wep = GetPlayerWeaponSlot(client, 2);
	if(!IsValidEntity(wep))
		return Plugin_Continue;

	if (wep != GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"))
		return Plugin_Continue;

	if(!HasEntProp(wep, Prop_Send, "m_bReadyToBackstab"))
		return Plugin_Continue;

	TraceRay trace;
	if (!DoSwingTrace(client, trace))
	{
		delete trace;
		return Plugin_Continue;
	}

	int ent = trace.EntityIndex;
	delete trace;

	if (ent == -1)
		return Plugin_Continue;

	if (GetEntProp(ent, Prop_Send, "m_iTeamNum") == GetClientTeam(client))
		return Plugin_Continue;

	if (!IsBehindTarget(client, ent))
		return Plugin_Continue;

	SetEntProp(wep, Prop_Send, "m_bReadyToBackstab", 1);
	result = true;
	
	return Plugin_Changed;
}

public void OnEntityCreated(int ent, const char[] classname)
{
	if (!strcmp(classname, "headless_hatman", false)
	 || !strcmp(classname, "merasmus", false)
	 || !strcmp(classname, "eyeball_boss", false)
//	 || !strcmp(classname, "tf_zombie", false)
	  )
	  	SDKHook(ent, SDKHook_Spawn, OnBossSpawn);
}

public Action OnBossSpawn(int ent)
{
	if (bEnabled.BoolValue)
		SDKHook(ent, SDKHook_OnTakeDamage, OnTakeDamage);

	return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!HasEntProp(weapon, Prop_Send, "m_bReadyToBackstab"))
		return Plugin_Continue;

	if (!GetEntProp(weapon, Prop_Send, "m_bReadyToBackstab"))
		return Plugin_Continue;

	int vm = GetEntPropEnt(attacker, Prop_Send, "m_hViewModel");
	if (vm > MaxClients && IsValidEntity(vm))
	{
		int anim = 15;
		switch (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"))
		{
			case 727:anim = 41;
			case 4, 194, 665, 794, 803, 883, 892, 901, 910:anim = 10;
			case 638:anim = 31;
		}
		SetEntProp(vm, Prop_Send, "m_nSequence", anim);
	}

	EmitSoundToAll("player/spy_shield_break.wav", attacker, _, SNDLEVEL_TRAFFIC, SND_NOFLAGS, 1.0, 100, _, _, NULL_VECTOR, true, 0.0);
	EmitSoundToAll("player/crit_received3.wav", attacker, _, SNDLEVEL_TRAFFIC, SND_NOFLAGS, 1.0, 100, _, _, NULL_VECTOR, true, 0.0);

	float delay = cvDelay.FloatValue, time = GetGameTime();
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", delay + time);
	SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", delay + time);
	
	damage = cvDamage.FloatValue;
	return Plugin_Changed;
}

// bool CTFWeaponBaseMelee::DoSwingTrace( trace_t &trace )
bool DoSwingTrace(int client, TraceRay &trace)
{
	static float vecSwingMins[3] = { -18.0, -18.0, -18.0 };
	static float vecSwingMaxs[3] = { 18.0, 18.0, 18.0 };

	// Setup the swing range.
	float vecForward[3];
	float vecEyes[3]; GetClientEyeAngles(client, vecEyes);
	GetAngleVectors(vecEyes, vecForward, NULL_VECTOR, NULL_VECTOR);
	float vecSwingStart[3]; GetClientEyePosition(client, vecSwingStart);

	ScaleVector(vecForward, 48.0);
	float vecSwingEnd[3]; vecSwingEnd = vAddVectors(vecSwingStart, vecForward);

	// See if we hit anything.
	trace = new TraceRay(vecSwingStart, vecSwingEnd, MASK_SOLID, RayType_EndPoint, Check4Bosses, client);
	if (trace.Fraction >= 1.0)
	{
		trace = TraceRay.AsHullFilter(vecSwingStart, vecSwingEnd, vecSwingMins, vecSwingMaxs, MASK_SOLID, Check4Bosses, client);
		/*if (trace.Fraction < 1.0)
		{
			// Calculate the point of intersection of the line (or hull) and the object we hit
			// This is and approximation of the "best" intersection
			int pHit = trace.EntityIndex;
			if ( !pHit || pHit->IsBSPModel() )
			{
				// Why duck hull min/max?
				FindHullIntersection( vecSwingStart, trace, VEC_DUCK_HULL_MIN, VEC_DUCK_HULL_MAX, pPlayer );
			}

			// This is the point on the actual surface (the hull could have hit space)
			trace.GetEndPosition(vecSwingEnd);	
		}*/
	}

	return (trace.Fraction < 1.0);
}

public bool Check4Bosses(int ent, int mask, any data)
{
	char classname[32]; GetEntityClassname(ent, classname, 32);
	if (!strcmp(classname, "headless_hatman", false)
	 || !strcmp(classname, "merasmus", false)
	 || !strcmp(classname, "eyeball_boss", false)
//	 || !strcmp(classname, "tf_zombie", false)
	  )
		return true;

	return ent != data;
}

// bool CTFKnife::IsBehindTarget( CBaseEntity *pTarget )
bool IsBehindTarget(int client, int ent)
{
	// Get the forward view vector of the target, ignore Z
	float vecVictimForward[3];
	float vecEyes[3]; GetEntPropVector(ent, Prop_Data, "m_angRotation", vecEyes);
	GetAngleVectors(vecEyes, vecVictimForward, NULL_VECTOR, NULL_VECTOR);
	vecVictimForward[2] = 0.0;
	float vecVictimForward2[3];	NormalizeVector(vecVictimForward, vecVictimForward2);

	// Get a vector from my origin to my targets origin
	float vecToTarget[3]; vecToTarget = vSubtractVectors(vWorldSpaceCenter(ent), vWorldSpaceCenter(client));
	vecToTarget[2] = 0.0;
	float vecToTarget2[3]; NormalizeVector(vecToTarget, vecToTarget2);

	float flDot = GetVectorDotProduct(vecVictimForward2, vecToTarget2);

	return (flDot > -0.1);
}

stock float[] vAddVectors(const float vec1[3], const float vec2[3])
{
	float result[3];
	result[0] = vec1[0] + vec2[0];
	result[1] = vec1[1] + vec2[1];
	result[2] = vec1[2] + vec2[2];
	return result;
}

stock float[] vSubtractVectors(const float vec1[3], const float vec2[3])
{
	float result[3];
	result[0] = vec1[0] - vec2[0];
	result[1] = vec1[1] - vec2[1];
	result[2] = vec1[2] - vec2[2];
	return result;
}

stock float[] vWorldSpaceCenter(int client)
{
	float result[3]; SDKCall(hWorldSpaceCenter, client, result);
	return result;
}