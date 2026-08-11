# Соло-рейды Injustice 2 Mobile 6.7.1 — клиент и сервер

Всё ниже снято из таблиц рефлексии UE4 в бинаре `Injustice2Mobile`
(build 1438123, UUID `2c66bd15-78e2-3cab-b3f6-2be3ff279a18`). Смещения и
размеры — фактические. Там, где данные не подтверждаются бинарём, это
отмечено явно.

> Этот файл заменяет более ранний отчёт, в котором структуры запросов были
> реконструированы «по смыслу»: имена полей вроде `TotalDamageDealt`,
> `bIsWinner`, `BattleSessionID`, `DefendersTotalDamageDealt` в бинаре
> отсутствуют.

---

## 1. Что уходит на сервер и что возвращается

### Завершение боя

```
FCompleteSoloRaidBattleRequest            size 0x60
   +0x00  FName          RaidTemplateKey
   +0x0C  FName          RaidInstanceID
   +0x18  int32          BattleIndex
   +0x1C  EDifficulty    Difficulty
   +0x20  int32          Level
   +0x24  FName          BossCharacterID
   +0x30  FMatchSummary  MatchSummary        <- единственный источник урона
   +0x58  bool           BattlePassActive
```

Отдельного поля с уроном **нет**. Всё, что сервер знает о бое, лежит в
`MatchSummary`:

```
FMatchSummary                             size 0x28
   +0x00  bool                       bPlayerWon
   +0x01  bool                       bPlayerQuit
   +0x02  bool                       bUsedAutoPlay
   +0x03  EGameModeType              GameMode
   +0x04  int32                      LastActivePlayerCharacterIndex
   +0x08  TArray<FPlayerMatchStats>  PlayerStats
   +0x18  TArray<FPlayerMatchStats>  OpponentStats
```

```
FPlayerMatchStats                         size 0x208
   +0x00  int32                 MaxHealth
   +0x04  int32                 Health
   +0x08  int32                 ThreatValue
   +0x0C  int32                 TotalDamageTaken
   +0x10  int32                 TotalDamageInflicted     <- урон по боссу
   +0x14  int32                 EffectiveDamageTaken
   +0x18  int32                 EffectiveHealthRestorationReceived
   +0x1C  int32                 MaxComboCount
   +0x20  TMap<FString,int32>   DamageInflictedPerOpponent
   +0x70  float                 TotalTimeActive
   +0x78  TArray<FKORecord>     KORecords
   +0x88  int32                 TotalKnockedOut
   +0x8C  int32                 TotalSwapIn
   +0x90  int32                 TotalBasicAttacks
   +0x94  FName                 CharacterType
   +0xB0  TMap<ECombatAttackType,int32>  TotalAttacksPerformed
```

### Ответ

```
FCompleteSoloRaidBattleResponse           size 0xC0
   +0x00  FSoloRaidProgressionData  ActiveProgression
   +0x60  FRewardsReceipt           Rewards
   +0x70  FBattleValidationData     BattleValidationData
```

### Старт боя

```
FStartSoloRaidBattleResponse              size 0x168
   +0x00  bool                          bAllowedToStart
   +0x08  TArray<FCharacterDefinition>  PlayerCharacters
   +0x18  TArray<FCharacterDefinition>  AICharacters
   +0x28  FBattleData                   Battle
```

Токена сессии в ответе нет. При отказе (`bAllowedToStart = false`) массивы
персонажей и `Battle` пустые — то есть локально «разрешить» старт бессмысленно,
запускать будет нечего.

### Отказ по валидации

```
FSoloRaidBattleInvalidError               size 0x50
   +0x00  int32                  CustomErrorCode
   +0x04  FBattleValidationData  BattleValidation
```

---

## 2. Серверное состояние прогресса

```
FSoloRaidProgressionData                  size 0x60
   +0x00  FName                              soloRaidTemplateID
   +0x0C  int32                              difficulty
   +0x10  int32                              currentLevel
   +0x18  FDateTime                          lastRetryUpdateTime
   +0x20  TArray<FSoloRaidLevelProgression>  soloRaidProgressionDataPerLevel
   +0x30  int32                              version
   +0x34  FName                              soloRaidId
   +0x40  int32                              selectedLevel
   +0x44  int32                              maxCompletedDifficulty
   +0x48  bool                               hasSeenUnlockedHeroModePopup
   +0x50  TArray<int32>                      lastBattlesDealtDamage
```

```
FSoloRaidLevelProgression                 size 0x28
   +0x00  TArray<FSoloRaidBattleProgression>  BattleProgressionPerLevel
   +0x10  TArray<FBattleValidationData>       LastWonBattleValidationDataPerLevel
   +0x20  int32                               battleIndex
   +0x24  bool                                hasSeenIntro
```

```
FSoloRaidBattleProgression                size 0x18
   +0x00  FDateTime  lastCompletionTime
   +0x08  int32      completionDifficulty
   +0x0C  int32      damageDealtToBoss
   +0x10  bool       isBossDead
   +0x11  bool       hasSeenDefeat
   +0x14  int32      lostBattles
```

Два поля здесь важнее прочих.

**`lastBattlesDealtDamage`** — сервер хранит историю урона за последние бои.
Сколько именно, задаётся в `FSoloRaidGlobalData.BattlesStoredForAverageDamageStatisticsAmount`.
То есть оценивается не отдельный бой, а **ряд**: резкий скачок относительно
собственной истории виден без всяких эталонов.

**`LastWonBattleValidationDataPerLevel`** — сервер держит валидационные данные
выигранных боёв по уровням, а не выбрасывает их после проверки.

---

## 3. Античит

```
FCheatDetectionGlobalData                 size 0x50
   +0x00  TMap<EGameModeType, FCheatDetectionData>  CheatDetectionDataMap
```

Конфигурация **отдельная для каждого режима игры**. Пороги в соло-рейдах не
обязаны совпадать с кампанией.

```
FCheatDetectionData                       size 0x9C   (25 полей)
   +0x00  ECheatDetectionServerType  CheatDetectionServerType

   веса подозрения                     границы нормы
   +0x04  AutoPlaySuspicionWeight
   +0x08  OpponentThreatRatioSuspicionWeight        +0x2C Min  +0x30 Max
   +0x0C  PlayerDPSRatioSuspicionWeight             +0x34 Min  +0x38 Max
   +0x10  PlayerDamageReceivedRatioSuspicionWeight  +0x3C Min
   +0x14  PlayerEffectiveDamageReceivedRatio…       +0x40 Max
   +0x18  BattleDurationSuspicionWeight             +0x44 Min  +0x48 Max
   +0x1C  MaxBattleDurationSuspicionWeight
   +0x20  PlayerBasicsPerSecondSuspicionWeight      +0x4C Min  +0x50 Max
   +0x24  PlayerSwapsPerSecondSuspicionWeight       +0x54 Min  +0x58 Max
   +0x28  PlayerSpecialsPerSecondSuspicionWeight    +0x5C Min  +0x7C Max
```

Это **взвешенная сумма**, а не набор независимых порогов: каждая метрика имеет
свой вес, и подозрения складываются.

Считается всё из `FMatchSummary`, который отправляет клиент:

| Метрика | Откуда берётся |
|---|---|
| `PlayerDPSRatio` | `TotalDamageInflicted` / `TotalTimeActive` относительно `ThreatValue` |
| `BattleDuration` | `TotalTimeActive` |
| `PlayerDamageReceivedRatio` | `TotalDamageTaken` — ноль читается как неуязвимость |
| `PlayerBasicsPerSecond` | `TotalBasicAttacks` / длительность |
| `PlayerSwapsPerSecond` | `TotalSwapIn` / длительность |
| `PlayerSpecialsPerSecond` | `TotalAttacksPerformed` / длительность |
| `OpponentThreatRatio` | угроза противника против своей |
| `UsedAutoPlay` | `bUsedAutoPlay` |

Результат возвращается клиенту:

```
FBattleValidationData                     size 0x4C
   +0x04  int32  PlayerCheatCount
   +0x08  float  CheatDetectionScalar
   +0x0C  bool   IsValid
   +0x0D  bool   UsedAutoPlay
   +0x10  float  OpponentThreatRatio
   +0x14  float  PlayerDPSRatio
   +0x18  float  PlayerDamageReceivedRatio
   +0x1C  float  PlayerEffectiveDamageReceivedRatio
   +0x20  float  BattleDuration
   +0x24  float  PlayerBasicsPerSecond
   +0x28  float  PlayerSwapsPerSecond
   +0x2C  float  PlayerSpecialsPerSecond
```

`PlayerCheatCount` — накопительный счётчик, а не флаг одного боя.

`ECheatDetectionServerType`: `Disabled` / `DevOnly` / `ProdOnly` / `DevAndProd` —
проверку можно включать раздельно на dev и prod.

---

## 4. Лимиты и экономика

```
FSoloRaidGlobalData                       size 0x100
   +0x00  MinProfileLevelRequiredToPlay
   +0x04  NumberOfDifficulties
   +0x08  AddAttemptsPerRefreshInterval
   +0x0C  AddBonusAttemptsPerRefreshInterval
   +0x10  MaxAvailableAttempts
   +0x14  MaxAvailablePremiumAttempts
   +0x18  MaxAvailableTrainingAttempts
   +0x1C  MaxAvailableIAPPurchase
   +0x20  RefreshIntervalsPerDay
   +0x24  NonPremiumRaidExpirationDays
   +0x28  CharactersRefreshIntervalsPerDay
   +0x2C  MaxDifficultyIndexWithoutExhaustion
   +0x30  BattlesStoredForAverageDamageStatisticsAmount
   +0xD8  BonusAttemptsCap
   +0xDC  MaxAvailableRerolls
   +0xF8  BattleTimeoutInHours
```

Это **описание полей, а не значения**. Сами числа приходят с сервера через
`UServerSoloRaidGlobalData` — в бинаре их нет, и любые конкретные цифры
(«6 попыток в день») бинарём не подтверждаются.

---

## 5. Клиентская сторона

```
USoloRaidManager           : UObject        логика режима
USoloRaidTrainingManager   : UObject        тренировочные бои
USoloRaidData              : UObject        активный экземпляр
USoloRaidHubMenu           : UMenuBase      хаб выбора уровня
USoloRaidManagementMenu    : URaidManagementMenu
USoloRaidAlbumMenu         : UMenuBase
USoloRaidAchievementsMenu  : UMenuBase
UPreFightMenuCachedState_SoloRaid : UBasePreFightMenuCachedState
UInboxSoloRaidMessageData  : UInboxMessageData
```

Проверки режима в бою (`ACombatGameMode`):

```
0x2124A8C  IsAnySoloRaidTemplateActive()
0x2124AFC  IsSoloRaidTemplateActive()
0x2124B78  GetActiveSoloRaidTemplateID()
0x2124B9C  GetActiveSoloRaidDifficulty()
```

Это exec-адреса; для хука нужны реальные функции — достаются
дизассемблированием переходника, как описано в `HANDOFF.md`.

---

## 6. Dev-читы

`UFrontendCheatManager` содержит рабочие имена: `CheatKillSoloRaidBoss`
(`0x215D75C`), `CheatKillAllSoloRaidBosses` (`0x215D7E8`),
`CheatConsumeSoloRaidAttempts` (`0x215D904`),
`CheatOverrideSoloRaidAverageDealtDamage` (`0x215D5BC`),
`CheatOpenSoloRaidPreFightMenu` (`0x215D8B0`) и другие. Плюс UI-плитка
`UCheatSoloRaidTile` с `WinSoloRaidBattle`, `KillAllSoloRaidBosses`,
`StartSoloRaid`, `ResetSoloRaidBattle`.

Все они выполняют **клиентские действия**, а результат всё равно уходит через
`CompleteSoloRaidBattleRequest` и проходит ту же валидацию. Их наличие в
бинаре не означает, что сервер примет результат.

---

## 7. Практические выводы для твика

**Урон по боссу считает сервер.** `damageDealtToBoss` — серверное поле, клиент
его не присылает. Влиять на него можно только через `TotalDamageInflicted`
внутри `MatchSummary`, а это статистика, которую накапливает сам движок.

**Смерть босса и урон — независимые поля.** `isBossDead` выставляется по
нокауту (`KORecords` / `TotalKnockedOut`), а `damageDealtToBoss` — по сумме
урона. Если менять HP в обход конвейера урона, эти два числа расходятся:
нокаут есть, урона под него нет. Под такое расхождение существует
`FSoloRaidBattleInvalidError`.

Именно поэтому масштабирование урона вынесено в хук
`ACombatCharacter::DamageCharacter` (`0x1B57088`), а не в запись HP: там
изменение попадает в собственный учёт игры и оба поля остаются
согласованными.

**Согласованность не равна незаметности.** Даже когда отчёт внутренне
непротиворечив, его числа сравниваются с порогами и с собственной историей
игрока (`lastBattlesDealtDamage`). Множитель урона поднимает `PlayerDPSRatio`,
авто-завершение опускает `BattleDuration`, отсутствие ввода обнуляет
`PlayerBasicsPerSecond` — все три имеют собственные веса в
`FCheatDetectionData`.

**Клиентских рычагов к наградам нет.** Награды приходят в `FRewardsReceipt`
внутри ответа сервера и попадают в Inbox. Ни попытки, ни валюта, ни прогресс
локально не редактируются.
