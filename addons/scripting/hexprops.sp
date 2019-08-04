#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <hexprops>
#include <hexstocks>

#define PLUGIN_AUTHOR         "Hexah and lbvf336"
#define PLUGIN_VERSION        "1.1"

#pragma semicolon 1
#pragma newdecls required

//Handle
Handle fOnPressProp;
//Int
int iEntHP[MAX_ENTITIES];

//Boolean
bool bMoveProp[MAXPLAYERS+1];
bool bPhysicProp[MAXPLAYERS+1];

//String
char sPropPath[PLATFORM_MAX_PATH];
char g_sTranslite[256];

//Kv
KeyValues PropKv;

//Arrays
ArrayList PropsArray;

#include HexProps/model_moving.sp

//Plugin Info
public Plugin myinfo =
{
	name = "HexProps",
	author = PLUGIN_AUTHOR,
	description = "Place, edit & save props!",
	version = PLUGIN_VERSION,
	url = "github.com/Hexer10/HexProps"
};

//Startup
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	
	RegPluginLibrary("hexprops");
	CreateNative("IsEntProp", Native_IsEntProp);
	
	fOnPressProp = CreateGlobalForward("OnPlayerPressProp", ET_Ignore, Param_Cell, Param_Cell);
}

public void OnPluginStart()
{
	PropsArray = new ArrayList();
	
	RegAdminCmd("sm_props", Cmd_Props, ADMFLAG_CONFIG);
	
	LoadTranslations("hexprops.phrases.txt");
	
	if (!HookEventEx("round_poststart", Event_RoundStart))
		if (!HookEventEx("round_start", Event_RoundStart))
			if (!HookEventEx("dod_round_start", Event_RoundStart))
				SetFailState("Unable to hook any round start event!");
}

public void OnMapStart()
{
	PreparePropKv();
}

//читаем
void PreparePropKv()
{
	char sMap[64], sId[64];
	GetCurrentMap(sMap, sizeof(sMap));
	
	if(StrContains(sMap, "workshop", false) != -1)
	{
		GetCurrentWorkshopMap(sMap, sizeof(sMap), sId, sizeof(sId));
		BuildPath(Path_SM, sPropPath, sizeof(sPropPath), "configs/props/workshop/%s", sId);
		if(!FileExists(sPropPath)) CreateDirectory(sPropPath, 511);
		BuildPath(Path_SM, sPropPath, sizeof(sPropPath), "configs/props/workshop/%s/%s.props.txt", sId, sMap);
	}
	else BuildPath(Path_SM, sPropPath, sizeof(sPropPath), "configs/props/%s.props.txt", sMap); //Get the right "map" file
	PropKv = new KeyValues("Props");
	
	if (!FileExists(sPropPath)) //Try to create kv file.
		if (!PropKv.ExportToFile(sPropPath))
			SetFailState(" - Props - Unable to (Kv)File: %s", sPropPath);
	
	if (!PropKv.ImportFromFile(sPropPath)) //Import the kv file
		SetFailState("- Props - Unable to import: %s", sPropPath);
}

void GetCurrentWorkshopMap(char[] sMap, int Path_SM, char[] sId, int iSizeId)
{
	char sExplodeBuffer[2][64];
	GetCurrentMap(sPropPath, sizeof(sPropPath));
	
	ReplaceString(sPropPath, sizeof(sPropPath), "workshop/", "", false);
	ExplodeString(sPropPath, "/", sExplodeBuffer, 2, 64);
	
	strcopy(sMap, Path_SM, sExplodeBuffer[1]);
	strcopy(sId, iSizeId, sExplodeBuffer[0]);
} 

//Commands
public Action Cmd_Props(int client, int args)
{
	CreateMainMenu(client).Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

//Events
public void OnClientDisconnect(int client)
{
	bMoveProp[client] = false;
	bPhysicProp[client] = false;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	PropsArray.Clear();
	LoadProps();
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	Moving_OnPlayerRunCmd(client, buttons);
	
	if (buttons & IN_USE)
	{
		int iEnt = GetAimEnt(client);
		
		if (FindInArray(iEnt) == -1)
		{
			Call_StartForward(fOnPressProp);
			Call_PushCell(client);
			Call_PushCell(iEnt);
			Call_Finish();
		}
	}
}


//Menu
Menu CreateMainMenu(int client)
{
	//Prepare MainMenu
	Menu MainMenu = new Menu(Handler_Main);
	
	MainMenu.SetTitle("%t", "Props menu");
	
	
	char sMoveDisplay[32];
	char sPhysicDisplay[32];
	Format(sMoveDisplay, sizeof(sMoveDisplay), "%t", "Movedd", bMoveProp[client]? "On" : "Off");
	Format(sPhysicDisplay, sizeof(sPhysicDisplay), "%t", "Physicdd", bPhysicProp[client]? "On" : "Off");
	
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Place New Prop");
	MainMenu.AddItem("Place", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Remove Props");
	MainMenu.AddItem("Remove", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Edit Props");
	MainMenu.AddItem("Edit", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Save Props");
	MainMenu.AddItem("Safe", g_sTranslite);
	MainMenu.AddItem("Move", sMoveDisplay);
	MainMenu.AddItem("Physic", sPhysicDisplay);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Reset Props");
	MainMenu.AddItem("Reset", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Delete All Props");
	MainMenu.AddItem("DeleteAll", g_sTranslite);
	
	return MainMenu;
}

Menu CreatePropMenu()
{
	//Prepare PropMenu
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/props/props_list.txt"); //Get prop_list file
	
	KeyValues kv = new KeyValues("Props");
	
	if (!kv.ImportFromFile(sPath))
		SetFailState("- Props - Unable to import: %s", sPath);
	
	if (!kv.GotoFirstSubKey())
		SetFailState(" - Props - Unable to read: %s", sPath);
	
	Menu PropMenu = new Menu(Handler_Props);
	
	PropMenu.SetTitle("Props");
	
	do //Loop all kv keys
	{
		char sName[64];
		char sModel[PLATFORM_MAX_PATH];
		
		kv.GetSectionName(sName, sizeof(sName));
		kv.GetString("model", sModel, sizeof(sModel));
		PropMenu.AddItem(sModel, sName);
	}
	while (kv.GotoNextKey());
	
	delete kv;
	
	PropMenu.ExitBackButton = true;
	
	return PropMenu;
}

Menu CreateEditMenu()
{
	//Prepare EditMenu
	Menu EditMenu = new Menu(Handler_Edit);
	
	EditMenu.SetTitle("%t", "Edit");
	
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Set Transparency");
	EditMenu.AddItem("Alpha", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Set Color");
	EditMenu.AddItem("Color", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Set LifePoints");
	EditMenu.AddItem("Life", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Set Consistency");
	EditMenu.AddItem("Solid", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Set Size");
	EditMenu.AddItem("Size", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Make Physic");
	EditMenu.AddItem("Physic", g_sTranslite);
	
	EditMenu.ExitBackButton = true;
	
	return EditMenu;
}

Menu CreateDeleteAllMenu()
{
	Menu DeleteAllMenu = new Menu(Handler_DeleteAll);
	
	DeleteAllMenu.SetTitle("%t", "Are you sure");
	
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "If you want to go back");
	DeleteAllMenu.AddItem("", g_sTranslite, ITEMDRAW_DISABLED);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "after you deleted the props");
	DeleteAllMenu.AddItem("", g_sTranslite, ITEMDRAW_DISABLED);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "press Reset Props and do NOT save the props");
	DeleteAllMenu.AddItem("", g_sTranslite, ITEMDRAW_DISABLED);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "NO");
	DeleteAllMenu.AddItem("0", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "YES");
	DeleteAllMenu.AddItem("1", g_sTranslite);
	
	DeleteAllMenu.ExitBackButton = true;
	return DeleteAllMenu;
}

Menu CreateColorMenu()
{
	//Prepare ColorMenu
	Menu ColorMenu = new Menu(Handler_Color);
	
	ColorMenu.SetTitle("%t", "Color");
	
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Default");
	ColorMenu.AddItem("Default", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Red");
	ColorMenu.AddItem("Red", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Blue");
	ColorMenu.AddItem("Blue", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Green");
	ColorMenu.AddItem("Green", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Yellow");
	ColorMenu.AddItem("Yellow", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Pink");
	ColorMenu.AddItem("Pink", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Black");
	ColorMenu.AddItem("Black", g_sTranslite);
	
	ColorMenu.ExitBackButton = true;
	
	return ColorMenu;
}

Menu CreateAlphaMenu()
{
	//Prepare AlphaMenu
	Menu AlphaMenu = new Menu(Handler_Alpha);
	
	AlphaMenu.SetTitle("%t", "Trasparency");
	
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Full Visible");
	AlphaMenu.AddItem("255", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "75 Visible");
	AlphaMenu.AddItem("191", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Half Visible");
	AlphaMenu.AddItem("127", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "25 Visible");
	AlphaMenu.AddItem("63", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Invisible");
	AlphaMenu.AddItem("0", g_sTranslite);
	
	AlphaMenu.ExitBackButton = true;
	
	return AlphaMenu;
}

Menu CreateLifeMenu()
{
	//Prepare LifeMenu
	Menu LifeMenu = new Menu(Handler_Life);
	
	LifeMenu.SetTitle("%t", "LifePoints");
	
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Unbreakable");
	LifeMenu.AddItem("0", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "50HP");
	LifeMenu.AddItem("50", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "100HP");
	LifeMenu.AddItem("100", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "200HP");
	LifeMenu.AddItem("200", g_sTranslite);
	
	LifeMenu.ExitBackButton = true;
	
	return LifeMenu;
}

Menu CreateSolidMenu()
{
	Menu SolidMenu = new Menu(Handler_Solid);
	
	SolidMenu.SetTitle("%t", "Consistency");
	
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Solid");
	SolidMenu.AddItem("6", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "UnSolid");
	SolidMenu.AddItem("1", g_sTranslite);
	
	SolidMenu.ExitBackButton = true;
	
	return SolidMenu;
}

Menu CreateSizeMenu()
{
	Menu SizeMenu = new Menu(Handler_Size);
	
	SizeMenu.SetTitle("%t", "Size");
	
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Default");
	SizeMenu.AddItem("1.0", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Double");
	SizeMenu.AddItem("2.0", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Triple");
	SizeMenu.AddItem("3.0", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Quadruple");
	SizeMenu.AddItem("4.0", g_sTranslite);
	FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Half");
	SizeMenu.AddItem("0.5", g_sTranslite);
	
	SizeMenu.ExitBackButton = true;
	
	return SizeMenu;
}

//Menu Handlers
public int Handler_Main(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		
		if (StrEqual(info, "Place"))
		{
			CreatePropMenu().DisplayAt(param1, param2, MENU_TIME_FOREVER);
		}
		else if(StrEqual(info, "Remove"))
		{
			if (RemoveProp(param1))
			{
				PrintToChat(param1, "%t", "Prop successfully removed");
			}
			else
			{
				PrintToChat(param1, "%t", "Prop couldnt be found");
			}
			
			CreateMainMenu(param1).Display(param1, MENU_TIME_FOREVER);
		}
		else if(StrEqual(info, "Edit"))
		{
			CreateEditMenu().Display(param1, MENU_TIME_FOREVER);
		}
		else if (StrEqual(info, "Move"))
		{
			bMoveProp[param1] = !bMoveProp[param1];
			
			CreateMainMenu(param1).Display(param1, MENU_TIME_FOREVER);
		}
		else if (StrEqual(info, "Physic"))
		{
			bPhysicProp[param1] = !bPhysicProp[param1];
			
			CreateMainMenu(param1).Display(param1, MENU_TIME_FOREVER);
		}
		else if (StrEqual(info, "Safe"))
		{
			bool bSaved = SaveProps();
			if (bSaved)
			{
				PrintToChat(param1, "%t", "Props successfully saved");
			}
			else
			{
				PrintToChat(param1, "%t", "No props were saved");
			}
			CreateMainMenu(param1).Display(param1, MENU_TIME_FOREVER);
		}
		else if (StrEqual(info, "Reset"))
		{
			ResetProps();
			PrintToChat(param1, "%t", "Props successfully resetted");
			CreateMainMenu(param1).Display(param1, MENU_TIME_FOREVER);
		}
		else
		{
			CreateDeleteAllMenu().Display(param1, 20);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 1;
}

public int Handler_Props(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[PLATFORM_MAX_PATH];
		menu.GetItem(param2, info, sizeof(info));
		
		if (!IsModelPrecached(info))
			PrecacheModel(info);
		
		char sClass[64] = "prop_dynamic_override";
		if (bPhysicProp[param1])
		{
			strcopy(sClass, sizeof(sClass), "prop_physics_multiplayer");
		}

		SpawnTempProp(param1, sClass, info);
		CreatePropMenu().DisplayAt(param1, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_Cancel)
	{
		CreateMainMenu(param1).Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int Handler_Edit(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		
		if (StrEqual(info, "Alpha"))
		{
			CreateAlphaMenu().Display(param1, MENU_TIME_FOREVER);
		}
		else if (StrEqual(info, "Color"))
		{
			CreateColorMenu().Display(param1, MENU_TIME_FOREVER);
		}
		else if (StrEqual(info, "Life"))
		{
			CreateLifeMenu().Display(param1, MENU_TIME_FOREVER);
		}
		else if (StrEqual(info, "Solid"))
		{
			CreateSolidMenu().Display(param1, MENU_TIME_FOREVER);
		}
		else if (StrEqual(info, "Size"))
		{
			CreateSizeMenu().Display(param1, MENU_TIME_FOREVER);
		}
		else
		{
			MakePhysic(param1);
			CreateEditMenu().Display(param1, MENU_TIME_FOREVER);
		}
		
	}
	else if (action == MenuAction_Cancel)
	{
		CreateMainMenu(param1).Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void MakePhysic(int client)
{
	int iEnt = GetAimEnt(client);
	
	if (iEnt == -1)
	{
		PrintToChat(client, "%t", "Prop couldnt be found");
		return;
	}

	int iIndex = FindInArray(iEnt);

	if (!iIndex || iIndex == -1)
	{
		PrintToChat(client, "%t", "Prop couldnt be found");
		return;
	}

	char sModel[PLATFORM_MAX_PATH];
	float vPos[3];
	GetEntityModel(iEnt, sModel);
	GetEntityOrigin(iEnt, vPos);

	AcceptEntityInput(iEnt, "kill");
	PropsArray.Erase(iIndex);

	iEnt = -1;
	iEnt = CreateEntityByName("prop_physics_multiplayer");

	if (iEnt == -1)
	{
		PrintToChat(client, "%t", "Error occured while creating the physic prop");
		return;
	}

	DispatchKeyValue(iEnt, "Physics Mode", "1");
	SetEntityModel(iEnt, sModel);
	DispatchSpawn(iEnt);
	
	TeleportEntity(iEnt, vPos, NULL_VECTOR, NULL_VECTOR);

	PropsArray.Push(EntIndexToEntRef(iEnt));

}
public int Handler_DeleteAll(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		bool bDelete = view_as<bool>(StringToInt(info));
		
		if (bDelete)
		{
			if (!PropKv.GotoFirstSubKey())
				SetFailState("- HexProps - Failed to read: %s", sPropPath);
				
			do 
			{
				PropKv.DeleteThis();
			}
			while (PropKv.GotoNextKey());
			PropKv.Rewind();
			
			for (int i = 0; i < PropsArray.Length; i++)
			{
				int iEnt = EntRefToEntIndex(PropsArray.Get(i));
				if (iEnt == INVALID_ENT_REFERENCE)
					continue;
					
				AcceptEntityInput(iEnt, "kill");
			}
			FormatEx(g_sTranslite, sizeof(g_sTranslite), "%t", "Props deleted");
			ReplyToCommand(param1, g_sTranslite);
		}
		CreateMainMenu(param1).Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_Cancel)
	{
		CreateEditMenu().Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int Handler_Color(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int r, g, b;
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		
		if (StrEqual(info, "Red"))
		{
			r = 255;
		}
		else if (StrEqual(info, "Green"))
		{
			g = 255;
		}
		else if (StrEqual(info, "Blue"))
		{
			b = 255;
		}
		else if (StrEqual(info, "Pink"))
		{
			r = 255;
			g = 102;
			b = 178;
		}
		else if (StrEqual(info, "Yellow"))
		{
			r = 255;
			g = 255;
		}
		else if (StrEqual(info, "Default"))
		{
			r = 255;
			g = 255;
			b = 255;
		}
		else{} //if black dont to anything
		
		int iAimEnt = GetAimEnt(param1);
		
		if (FindInArray(iAimEnt) != -1)
		{
			int r2, g2, b2, a;
			
			GetEntityRenderColor(iAimEnt, r2, g2, b2, a);
			SetEntityRenderColor(iAimEnt, r, g, b, a);
		}
		else
		{
			PrintToChat(param1, "%t", "Prop couldnt be found");
		}
		
		CreateColorMenu().Display(param1, MENU_TIME_FOREVER);
		
	}
	else if (action == MenuAction_Cancel)
	{
		CreateEditMenu().Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int Handler_Alpha(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		
		int iAimEnt = GetAimEnt(param1);
		
		if (FindInArray(iAimEnt) != -1)
		{
			int r, g, b, a;
			SetEntityRenderMode(iAimEnt, RENDER_TRANSCOLOR);
			GetEntityRenderColor(iAimEnt, r, g, b, a);
			SetEntityRenderColor(iAimEnt, r, g, b, StringToInt(info));
		}
		else
		{
			PrintToChat(param1, "%t", "Prop couldnt be found");
		}
		
		CreateAlphaMenu().Display(param1, MENU_TIME_FOREVER);
		
	}
	else if (action == MenuAction_Cancel)
	{
		CreateEditMenu().Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int Handler_Life(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		
		int r, b, g, a;
		int iLife;
		
		int iAimEnt = GetAimEnt(param1);
		
		if (FindInArray(iAimEnt) != -1)
		{
			GetEntityRenderColor(iAimEnt, r, g, b, a);
			iLife = StringToInt(info);
			
			if (iLife)
			{
				iEntHP[iAimEnt] = iLife;
				SetEntProp(iAimEnt, Prop_Data, "m_takedamage", 2);
				SetEntProp(iAimEnt, Prop_Data, "m_iHealth", iLife);
			}
		}
		else
		{
			PrintToChat(param1, "%t", "Prop couldnt be found");
		}
		
		CreateLifeMenu().Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_Cancel)
	{
		CreateEditMenu().Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int Handler_Solid(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		
		int iAimEnt = GetAimEnt(param1);
		
		if (FindInArray(iAimEnt) != -1)
		{
			SetEntProp(iAimEnt, Prop_Send, "m_nSolidType", StringToInt(info));
		}
		else
		{
			PrintToChat(param1, "%t", "Prop couldnt be found");
		}
		
		CreateSolidMenu().Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_Cancel)
	{
		CreateEditMenu().Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int Handler_Size(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		
		int iAimEnt = GetAimEnt(param1);
		
		if (FindInArray(iAimEnt) != -1)
		{
			SetEntPropFloat(iAimEnt, Prop_Send, "m_flModelScale", StringToFloat(info));
		}
		else
		{
			PrintToChat(param1, "%t", "Prop couldnt be found");
		}
		
		CreateSizeMenu().Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_Cancel)
	{
		CreateEditMenu().Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

//Functions
int SpawnProp(const char[] classname, const char[] model, float vPos[3], float vAng[3], int r, int g, int b, int a, bool solid, int iLife, float fSize)
{
	int iEnt = CreateEntityByName(classname);
	
	if (iEnt == -1)
		return -1;
	
	if (!IsModelPrecached(model))
		PrecacheModel(model);
	
	SetEntityModel(iEnt, model);
	SetEntityRenderMode(iEnt, RENDER_TRANSCOLOR);
	SetEntityRenderColor(iEnt, r, b, g, a);
	
	SetEntProp(iEnt, Prop_Send, "m_nSolidType", 6);
	
	if (!solid)
		SetEntProp(iEnt, Prop_Send, "m_nSolidType", 1);
	
	if (iLife)
	{
		SetEntProp(iEnt, Prop_Data, "m_takedamage", 2);
		iEntHP[iEnt] = iLife;
		SetEntProp(iEnt, Prop_Data, "m_iHealth", iLife);
	}
	
	SetEntPropFloat(iEnt, Prop_Send, "m_flModelScale", fSize);
	
	if (StrContains(classname, "physics") != -1)
	{
		DispatchKeyValue(iEnt, "Physics Mode", "1");
		DispatchSpawn(iEnt);
	}

	TeleportEntity(iEnt, vPos, vAng, NULL_VECTOR);
	return iEnt;
}

int SpawnTempProp(int client, const char[] classname, const char[] model)
{
	int iEnt = CreateEntityByName(classname);
	
	if (iEnt == -1)
	{
		CreatePropMenu().Display(client, MENU_TIME_FOREVER);
		return -1;
	}
	
	SetEntityModel(iEnt, model);
	SetEntProp(iEnt, Prop_Send, "m_nSolidType", 6);
	SetEntityRenderMode(iEnt, RENDER_TRANSCOLOR);
	SetEntityRenderColor(iEnt);
	
	float vClientPos[3];
	float vClientAng[3];
	float vEndPoint[3];
	float vEndAng[3];
	
	GetClientEyePosition(client, vClientPos);
	GetClientEyeAngles(client, vClientAng);
	
	TR_TraceRayFilter(vClientPos, vClientAng, MASK_SOLID, RayType_Infinite, TraceRayDontHitPlayer, client);
	
	if (TR_DidHit())
	{
		TR_GetEndPosition(vEndPoint);
		TR_GetPlaneNormal(INVALID_HANDLE, vEndAng);
		GetVectorAngles(vEndAng, vEndAng);
		vEndAng[0] += 90.0;
	}
	else
	{
		CreatePropMenu().Display(client, MENU_TIME_FOREVER);
		return -1;
	}
	
	if (StrContains(classname, "physics") != -1)
	{
		DispatchKeyValue(iEnt, "Physics Mode", "1");
		DispatchSpawn(iEnt);
	}

	TeleportEntity(iEnt, vEndPoint, vEndAng, NULL_VECTOR);
	
	int iIndex = PropsArray.Push(EntIndexToEntRef(iEnt));
	
	SetEntityName(iEnt, "Prop_%i", iIndex);
	
	return iEnt;
}

bool RemoveProp(int client)
{
	int iAimEnt = GetAimEnt(client);
	int iIndex;
	
	if (iAimEnt == -1)
		return false;
	
	iIndex = FindInArray(iAimEnt) != -1;

	if (!iIndex)
		return false;
	
	AcceptEntityInput(iAimEnt, "kill");
	PropsArray.Erase(iIndex);
	
	return true;
}

bool SaveProps()
{
	ClearPropKv();
	
	char sKey[8];
	int iCount;
	bool bReturn = false;
	
	for (int i = 0; i < PropsArray.Length; i++)
	{
		PropKv.Rewind();
		IntToString(++iCount, sKey, sizeof(sKey));
		
		if (PropKv.JumpToKey(sKey, true))
		{
			int iEnt = EntRefToEntIndex(PropsArray.Get(i));
			
			if (iEnt == INVALID_ENT_REFERENCE)
				continue;
			
			char sClass[64];
			char sModel[PLATFORM_MAX_PATH];
			char sColor[16];
			float vPos[3];
			float vAng[3];
			int r, b, g, a;
			
			GetEntityClassname(iEnt, sClass, sizeof(sClass));
			GetEntityModel(iEnt, sModel);
			GetEntityOrigin(iEnt, vPos);
			GetEntityAngles(iEnt, vAng);
			GetEntityRenderColor(iEnt, r, g, b, a);
			bool solid = (GetEntProp(iEnt, Prop_Send, "m_nSolidType") == 6);
			int iLife = iEntHP[iEnt];
			float fSize = GetEntPropFloat(iEnt, Prop_Send, "m_flModelScale");
			
			ColorToString(sColor, sizeof(sColor), r, b, g, a);
			
			PropKv.SetString("classname", sClass);
			PropKv.SetString("model", sModel);
			PropKv.SetVector("position", vPos);
			PropKv.SetVector("angles", vAng);
			PropKv.SetString("color", sColor);
			PropKv.SetNum("solid", solid);
			PropKv.SetNum("life", iLife);
			PropKv.SetFloat("size", fSize);
			bReturn = true;
		}
	}
	PropKv.Rewind();
	PropKv.ExportToFile(sPropPath);
	return bReturn;
}

void LoadProps()
{
	if (!PropKv.GotoFirstSubKey())
		return;
	
	PropsArray.Clear();	
	do
	{
		char sClass[64];
		char sModel[PLATFORM_MAX_PATH];
		float vPos[3];
		float vAng[3];
		char sColors[16];
		int r, g, b, a;
		
		PropKv.GetString("classname", sClass, sizeof(sClass), "prop_dynamic_override");
		PropKv.GetString("model", sModel, sizeof(sModel));
		PropKv.GetVector("position", vPos);
		PropKv.GetVector("angles", vAng);
		PropKv.GetString("color", sColors, sizeof(sColors));
		
		bool solid = view_as<bool>(PropKv.GetNum("solid"));
		int iLife = PropKv.GetNum("life");
		float fSize = PropKv.GetFloat("size");
		
		StringToColor(sColors, r, g, b, a);
		int iEnt = SpawnProp(sClass, sModel, vPos, vAng, r, g, b, a, solid, iLife, fSize);
		
		if (iEnt != -1)
		{
			int iIndex = PropsArray.Push(EntIndexToEntRef(iEnt));
			SetEntityName(iEnt, "Prop_%i", iIndex);
		}
	}
	while (PropKv.GotoNextKey());
	
	PropKv.Rewind();
}

void ResetProps()
{
	for (int i = 0; i < PropsArray.Length; i++)
	{
		int iEnt = EntRefToEntIndex(PropsArray.Get(i));
		
		if (iEnt != INVALID_ENT_REFERENCE)
			AcceptEntityInput(iEnt, "kill");
	}
	PropsArray.Clear();
	
	LoadProps();
}

//Trace
public bool TraceRayDontHitPlayer(int entity, int mask, any data)
{
	if(entity != data && entity > MaxClients)
	{
		return true;
	}
	return false;
}

//Stocks
void ColorToString(char[] sColor, int maxlength, int r, int g, int b, int a)
{
	Format(sColor, maxlength, "%i %i %i %i", r, g, b, a);
}

void StringToColor(char[] sColors, int &r, int &g, int &b, int &a)
{
	char sColorsL[4][64];
	ExplodeString(sColors, " ", sColorsL, sizeof(sColorsL), sizeof(sColorsL[]));
	
	r = StringToInt(sColorsL[0]);
	g = StringToInt(sColorsL[1]);
	b = StringToInt(sColorsL[2]);
	a = StringToInt(sColorsL[3]);
}

void ClearPropKv()
{
	if (!PropKv.GotoFirstSubKey())
		return;
	
	do
	{
		PropKv.DeleteThis();
	}
	while (PropKv.GotoNextKey());
	
	PropKv.Rewind();
}

int FindInArray(int iEnt)
{
	//PrintToChatAll("%d", iEnt);	
	if (iEnt == -1)
		return 0;

	for (int i = 0; i < PropsArray.Length; i++)
	{
		//PrintToChatAll("%d | %d", iEnt, i);
		int iSavedEnt = EntRefToEntIndex(PropsArray.Get(i));
		
		if (iSavedEnt == INVALID_ENT_REFERENCE)
			return 0;

		if (iSavedEnt == iEnt)
		{
			return i;
		}
	}
	return 0;
}

//Use this(instead of GetClientAimTarget) since we need to get non-solid entites too.
int GetAimEnt(int client)
{
	float vClientPos[3];
	float vClientAng[3];
	
	GetClientEyePosition(client, vClientPos);
	GetClientEyeAngles(client, vClientAng);
	
	TR_TraceRayFilter(vClientPos, vClientAng, MASK_ALL, RayType_Infinite, TraceRayDontHitPlayer, client);
	
	int iEnt = TR_GetEntityIndex();
	
	if (iEnt == 0) //Make the ent = -1 even if the Trace hitted
		iEnt = -1;
	
	return iEnt;
}

//Natives
public int Native_IsEntProp(Handle plugin, int numParams)
{
	int iEnt = GetNativeCell(1);
	
	return (FindInArray(iEnt) == -1);
}
