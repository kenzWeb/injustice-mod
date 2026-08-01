// Injustice 2 Mobile — offsets for build 6.7.1 (CFBundleVersion 1438123)
// Mach-O UUID 2c66bd15-78e2-3cab-b3f6-2be3ff279a18
//
// Every value is an RVA from the image base (0x100000000). In this binary the
// __TEXT file offset equals the RVA, so these are also raw file offsets.
// They are version-locked: any game update invalidates them. The tweak refuses
// to hook if the running build does not match (see kExpectedBundleVersion).
#pragma once

#define kExpectedBundleVersion  @"1438123"
#define kExpectedShortVersion   @"6.7.1"

// ---- ACombatCharacter (size 0x1DC0) -----------------------------------------
// void ACombatCharacter::SetCurrentHealth(int32 NewHP)
//   x0 = this, w1 = requested HP. Clamps to [0, MaxHealth] then stores to +0x4E4.
//   Single choke point: damage, healing and init all funnel through it.
#define RVA_SetCurrentHealth        0x1B50954

// float ACombatCharacter::GetHealthPercentage() const  -> CurrentHealth / MaxHealth
#define RVA_GetHealthPercentage     0x1B4CFB4

#define OFF_CurrentHealth           0x4E4   // int32
#define OFF_MaxHealth               0x4E8   // int32
#define OFF_CharacterTeam           0x118C  // ECharacterTeam (roster faction, NOT side)

// ---- ABaseGameCharacter (size 0x640) ----------------------------------------
// bool ABaseGameCharacter::IsPlayerCharacter() — virtual, vtable byte offset 0x9A0
#define VT_IsPlayerCharacter        0x9A0

// ---- native exec thunks (UFunction) -----------------------------------------
#define RVA_exec_SetBaseHealth      0x210D98C
#define RVA_exec_GetBaseHealth      0x210D978
#define RVA_exec_RestoreHealth      0x210D9CC
#define RVA_exec_SetHealthPercent   0x210AFBC
#define RVA_exec_InitMaxHealth      0x2111C6C
