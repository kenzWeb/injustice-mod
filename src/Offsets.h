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
#define RVA_CampaignChapterInit     0x1D46D88
#define RVA_CampaignStartBattle     0x1D479B0
#define RVA_ResultsTransitionIn     0x1F3957C
#define RVA_ResultsOnContinue       0x1F39914
#define RVA_OnFightButtonClicked    0x1F4D690
#define RVA_RequirementsResult      0x1F625DC
#define OFF_RequirementsUnmet       0x750
#define RVA_IsStunned               0x1B490F8
#define RVA_IsFrozen                0x1B47CD0

#define OFF_CurrentHealth           0x4E4
#define OFF_MaxHealth               0x4E8
#define OFF_CharacterTeam           0x118C

#define OFF_ResourceCurrent         0xF8
#define OFF_ResourceMax             0xFC

#define VT_IsPlayerCharacter        0x9A0

#define SEG_TextEnd                 0x4B30000
#define SEG_ImageEnd                0x661C000
