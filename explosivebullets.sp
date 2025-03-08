#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = 
{
    name = "Explosive Thrust Bullets and Knife Boost",
    author = "YourName",
    description = "Bullets create explosion thrust and knife gives mega boost",
    version = "3.0",
    url = "http://yourwebsite.com"
};

// ConVars for customization
ConVar g_cvSelfDamage;      // Damage to shooter
ConVar g_cvOtherDamage;     // Damage to others
ConVar g_cvThrustForce;     // Thrust strength
ConVar g_cvThrustRadius;    // Thrust range
ConVar g_cvExplosionRadius; // Explosion and damage radius
ConVar g_cvKnifeBoostForce; // Knife boost force multiplier
ConVar g_cvKnifeDamage;     // Damage from knife boost

// Throttle to prevent spam
float g_fLastExplosionTime[MAXPLAYERS + 1];
const float THROTTLE_TIME = 0.1; // 0.1s cooldown for bullets

public void OnPluginStart()
{
    HookEvent("bullet_impact", Event_BulletImpact);
    HookEvent("weapon_fire", Event_WeaponFire);
    
    g_cvSelfDamage = CreateConVar("sm_thrustbullets_self_damage", "1.0", "Damage to shooter when thrust (0 to disable)", _, true, 0.0, true, 100000.0);
    g_cvOtherDamage = CreateConVar("sm_thrustbullets_other_damage", "5.0", "Damage to others when thrust (0 to disable)", _, true, 0.0, true, 100000.0);
    g_cvThrustForce = CreateConVar("sm_thrustbullets_force", "700.0", "Force to thrust the shooter away", _, true, 100.0, true, 100000.0);
    g_cvThrustRadius = CreateConVar("sm_thrustbullets_radius", "200.0", "Radius for thrust and damage", _, true, 10.0, true, 100000.0);
    g_cvExplosionRadius = CreateConVar("sm_thrustbullets_explosion_radius", "30.0", "Radius of explosion effect", _, true, 10.0, true, 100000.0);
    g_cvKnifeBoostForce = CreateConVar("sm_thrustbullets_knife_force", "1000.0", "Force multiplier for knife mega boost", _, true, 100.0, true, 100000.0);
    g_cvKnifeDamage = CreateConVar("sm_thrustbullets_knife_damage", "3.0", "Damage to player when using knife boost", _, true, 0.0, true, 100000.0);
    
    PrintToServer("Explosive Thrust Bullets plugin v3.0 with Knife Boost loaded!");
}

public void OnClientPutInServer(int client)
{
    g_fLastExplosionTime[client] = 0.0; // Reset throttle on join
    SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
    SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
    SDKUnhook(client, SDKHook_TraceAttack, OnTraceAttack);
}

public Action OnWeaponSwitch(int client, int weapon)
{
    // No special action needed here, but keeping the hook for future expansion
    return Plugin_Continue;
}

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    // We don't modify the trace attack, just continue
    return Plugin_Continue;
}

public void Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client || !IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    float currentTime = GetGameTime();
    if (currentTime - g_fLastExplosionTime[client] < THROTTLE_TIME)
        return;

    float impactPos[3];
    impactPos[0] = event.GetFloat("x");
    impactPos[1] = event.GetFloat("y");
    impactPos[2] = event.GetFloat("z");

    CreateExplosionAndThrust(impactPos, client, false);
    g_fLastExplosionTime[client] = currentTime;
}

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client || !IsClientInGame(client) || !IsPlayerAlive(client))
        return;
    
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));
    
    // Check if the weapon is a knife
    if (StrContains(weapon, "knife") != -1)
    {
        // Execute trace to find where the knife hit
        float eyePos[3], eyeAng[3], endPos[3];
        GetClientEyePosition(client, eyePos);
        GetClientEyeAngles(client, eyeAng);
        
        TR_TraceRayFilter(eyePos, eyeAng, MASK_SOLID, RayType_Infinite, TraceFilter_DontHitPlayers, client);
        
        if (TR_DidHit())
        {
            TR_GetEndPosition(endPos);
            
            // If the trace hit somewhere close enough to be a valid knife hit
            if (GetVectorDistance(eyePos, endPos) < 120.0)
            {
                CreateExplosionAndThrust(endPos, client, true);
                
                // Apply knife boost damage to the player
                float knifeDamage = g_cvKnifeDamage.FloatValue;
                if (knifeDamage > 0.0)
                {
                    SDKHooks_TakeDamage(client, client, client, knifeDamage, DMG_BLAST, -1, NULL_VECTOR, endPos);
                    PrintToServer("[Knife Boost] Player %d took %.1f self-damage", client, knifeDamage);
                }
                
                // Visual feedback for the player
                //PrintToChat(client, "\x04[Knife Boost]\x01 Mega boost activated!");
            }
        }
    }
}

public bool TraceFilter_DontHitPlayers(int entity, int contentsMask, any data)
{
    return (entity > MaxClients || entity < 1);
}

void CreateExplosionAndThrust(float impactPos[3], int shooter, bool isKnifeBoost)
{
    float explosionSize = isKnifeBoost ? g_cvExplosionRadius.FloatValue * 5.0 : g_cvExplosionRadius.FloatValue;
    float thrustRadius = isKnifeBoost ? g_cvThrustRadius.FloatValue * 1.5 : g_cvThrustRadius.FloatValue;
    
    // Visual explosion effect
    TE_SetupExplosion(impactPos, PrecacheModel("materials/sprites/zerogxplode.vmt"), 5.0, 1, 0, RoundToNearest(explosionSize), 2000);
    TE_SendToAll();
    
    // Sound for knife
    if (isKnifeBoost)
    {
        // Visual explosion effect
        EmitSoundToAll("weapons/explode3.wav", shooter, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE, _, 0.3, SNDPITCH_NORMAL, _, impactPos);
        //EmitSoundToAll("weapons/explode3.wav", shooter, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE, _, 0.3, SNDPITCH_NORMAL, _, impactPos);
        //TE_SendToAll();
    }

   //EmitSoundToAll("weapons/explode3.wav", shooter, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE, _, isKnifeBoost ? 0.3 : 0.1, SNDPITCH_NORMAL, _, impactPos);

    // Check shooter distance for thrust and damage
    float shooterPos[3];
    GetClientAbsOrigin(shooter, shooterPos);
    float distance = GetVectorDistance(impactPos, shooterPos);

    if (distance <= thrustRadius)
    {
        // Apply damage to all players in thrust radius (only for bullets, not knife boost)
        if (!isKnifeBoost)
        {
            for (int i = 1; i <= MaxClients; i++)
            {
                if (!IsClientInGame(i) || !IsPlayerAlive(i))
                    continue;

                float targetPos[3];
                GetClientAbsOrigin(i, targetPos);
                float targetDistance = GetVectorDistance(impactPos, targetPos);

                if (targetDistance <= thrustRadius)
                {
                    float damage = (i == shooter) ? g_cvSelfDamage.FloatValue : g_cvOtherDamage.FloatValue;
                    if (damage > 0.0)
                    {
                        SDKHooks_TakeDamage(i, shooter, shooter, damage, DMG_BLAST, -1, NULL_VECTOR, impactPos);
                        PrintToServer("[Damage] Player %d took %.1f damage at distance %.1f", i, damage, targetDistance);
                    }
                }
            }
        }

        // Calculate thrust force
        float thrustForce = isKnifeBoost ? g_cvKnifeBoostForce.FloatValue : g_cvThrustForce.FloatValue;
        
        // Thrust the shooter
        float direction[3];
        SubtractVectors(shooterPos, impactPos, direction);
        NormalizeVector(direction, direction);

        float velocity[3];
        GetEntPropVector(shooter, Prop_Data, "m_vecVelocity", velocity);
        ScaleVector(direction, thrustForce);
        AddVectors(velocity, direction, velocity);

        // Extra upward boost for knife
        if (isKnifeBoost)
        {
            velocity[2] += thrustForce * 0.5; // Add significant upward component
        }

        shooterPos[2] += 5.0; // Lift off ground
        TeleportEntity(shooter, shooterPos, NULL_VECTOR, NULL_VECTOR);
        TeleportEntity(shooter, NULL_VECTOR, NULL_VECTOR, velocity);

        PrintToServer("[%s] Player %d thrust at distance %.1f: X:%.1f Y:%.1f Z:%.1f", 
            isKnifeBoost ? "Knife Boost" : "Thrust", 
            shooter, distance, velocity[0], velocity[1], velocity[2]);
    }
}