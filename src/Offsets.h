#pragma once

#define kExpectedBundleVersion      @"1438123"
#define kExpectedShortVersion       @"6.7.1"

#define RVA_SetCurrentHealth        0x1B50954
#define RVA_GetHealthPercentage     0x1B4CFB4
#define RVA_ShowDamageMessage       0x1B4D8D8
#define RVA_TakeCombatDamage        0x1B4062C
#define RVA_DamageCharacter         0x1B57088

#define OFF_CurrentHealth           0x4E4
#define OFF_MaxHealth               0x4E8
#define OFF_CharacterTeam           0x118C

#define VT_IsPlayerCharacter        0x9A0

#define SEG_TextEnd                 0x4B30000
#define SEG_ImageEnd                0x661C000
