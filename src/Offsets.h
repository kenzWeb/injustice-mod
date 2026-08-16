#pragma once

#define kExpectedBundleVersion      @"1438123"
#define kExpectedShortVersion       @"6.7.1"

#define RVA_SetCurrentHealth        0x1B50954
#define RVA_GetHealthPercentage     0x1B4CFB4
#define RVA_ShowDamageMessage       0x1B4D8D8
#define RVA_TakeCombatDamage        0x1B4062C
#define RVA_DamageCharacter         0x1B57088

#define RVA_HasEnoughFunds          0x1B4E914
#define RVA_HasEnoughPower          0x1B4E874
#define RVA_HasEnoughEnergy         0x1B4E8C4
#define RVA_HasEnoughResource       0x1B457A0
#define RVA_GetPowerPercentage      0x1B4DEA8
#define RVA_GetCurrentPower         0x1B4E0F0
#define RVA_GetCurrentEnergy        0x1B4E110
#define RVA_GetResourceCurrent      0x3745874
#define RVA_BattleRequirementStates 0x1C99C38
#define RVA_TeamMeetsRequirements   0x1C998FC
#define RVA_KillCharacter           0x1B41710
#define RVA_CampaignChapterInit     0x1D46D88
#define RVA_CampaignCurrentBattleId 0x1D476E8
#define RVA_CampaignGoToFight       0x1D471A4
#define RVA_CampaignLadderView      0x1D477E8
#define RVA_CampaignLevelActor      0x1D46EB0
#define OFF_SummaryWindowData       0x338
#define OFF_SummaryFightButton      0x370
#define RVA_SimulateClick           0x1E27CB8
#define OFF_SummaryDataBattleName   0x40
#define OFF_SummaryDataLocked       0x60

#define RVA_SummaryWindowSetData    0x1D82254
#define RVA_SummaryWindowShown      0x1D82480
#define RVA_PreFightOpponentView    0x1F48668
#define RVA_PreFightStartFight      0x1F49A94
#define RVA_CampaignStartBattle     0x1D479B0
#define RVA_ResultsTransitionIn     0x1F3957C
#define RVA_ResultsOnContinue       0x1F39914
#define RVA_OnFightButtonClicked    0x1F4D690
#define RVA_RequirementsResult      0x1F625DC
#define OFF_RequirementsUnmet       0x750
#define RVA_ClaimSoloRaidBossRewards 0x1F9DE0C
#define RVA_GetSoloRaidManager      0x1B7A4BC
#define RVA_IsStunned               0x1B490F8
#define RVA_IsFrozen                0x1B47CD0

#define RVA_SoloRaidPopulateSummary 0x1FFEC44
#define RVA_RaidSummarySetData      0x1E4C578
#define RVA_RaidSummaryStartClicked 0x1E4C0DC
#define RVA_RaidSelectBoss          0x1F69B64
#define RVA_RaidStartBattleClicked  0x1F68838
#define RVA_InboxCreateMessageData  0x1E9B244

#define VT_RaidCanFight             0x658
#define VT_RaidStartBattle          0x660
#define VT_RaidUpdateSubBosses      0x6B0

#define OFF_RaidBossActors          0x4A0
#define OFF_RaidSelectedBoss        0x4B8
#define OFF_RaidInfoPanel           0x568
#define OFF_RaidRootPanel           0x558
#define OFF_RaidRootSummaryWindow   0x370
#define OFF_RaidSummaryData         0x338
#define OFF_RaidSummaryFightButton  0x358
#define OFF_RaidSummaryDataEnemy    0x338
#define OFF_RaidSummaryDataHealth   0x344
#define OFF_RaidSummaryDataMax      0x348

#define OFF_RaidBossBattleIndex     0x30
#define OFF_RaidBossHealthCurrent   0xB4
#define OFF_RaidBossHealthMax       0xB8

#define OFF_RaidInfoPipsBox         0x370
#define OFF_PipsCommon              0x34C
#define OFF_PipsBonus               0x350
#define OFF_PipsPremium             0x354

#define OFF_InboxClaimAllButton     0x3C0

#define OFF_MgrCachedDifficulty     0x64
#define OFF_MgrCachedBattleIndex    0x68
#define OFF_MgrCachedLevel          0x6C

#define OFF_CurrentEnemy            0x500
#define OFF_CurrentHealth           0x4E4
#define OFF_MaxHealth               0x4E8
#define OFF_CharacterTeam           0x118C

#define OFF_ResourceCurrent         0xF8
#define OFF_ResourceMax             0xFC

#define VT_IsPlayerCharacter        0x9A0

// --- UFrontendCheatManager construction (ProcessEvent path) ---
// Found via static vtable reconstruction of __DATA_CONST,__const (5073 vtables).
#define RVA_FrontendCheatMgrStaticClass 0x2163B90  // UFrontendCheatManager::StaticClass() -> UClass*
#define RVA_GetPlayerController         0x37F9BB4  // UGameplayStatics::GetPlayerController real impl (worldCtx, index)
#define RVA_FNameCtor                   0x24C6268  // FName::FName(FName* out, const char* str, EFindName) (12-byte FName)
#define VT_ProcessEvent                 0x228      // UObject vtable slot (default impl RVA 0x25FEBB0, 0 direct callers)
#define VT_FindFunction                 0x160      // UObject vtable slot (reads this->Class +0x10, dispatches FindFunctionByName)
#define VT_EnableCheats                 0xA88      // APlayerController vtable slot (constructs CheatManager)
#define OFF_UObjectClass                0x10       // UObject::ClassPrivate
#define OFF_PCCheatManager              0x350      // APlayerController::CheatManager
#define OFF_PCCheatClass                0x358      // APlayerController::CheatClass (TSubclassOf)

#define SEG_TextEnd                 0x4B30000
#define SEG_ImageEnd                0x661C000
