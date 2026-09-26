# Exact HyperOS target-system audit

- role: original Xiaomi yingtian China OS4.0.11.0.XBMCNXM based system image supplied for the Lenovo port
- scope: read-only classpath comparison with the supplied stock TB350FU runtime
- no Lenovo framework file is copied into this image by the audit

## Input image
```
input/system_hyperos4_p11g2.img 920039464 B
8b71ea568dfb6043cfb3234372b3b672c30f9dfb2e81d11ed1bbae89e98dc14f  input/system_hyperos4_p11g2.img
target-audit/system.raw.img: EROFS filesystem, compat: SB_CHKSUM MTIME, blocksize=12, exslots=0, uuid=22EBB767-BB3E-214C-8B01-8FF545F10D8D, incompat: LZ4_0PADDING
```

## Target classpath inventory
```
target-audit/system.root/system/etc/classpaths/systemserverclasspath.pb 194 B
target-audit/system.root/system/framework/oat/arm64/services.odex 7420408 B
target-audit/system.root/system/framework/oat/arm64/services.vdex 488896 B
target-audit/system.root/system/framework/services.jar 39875204 B
5f843d27d48abb06979f99bfe63cac925652ed67a460b3d3418a1a1b8e128680  target-audit/system.root/system/framework/services.jar
```

## Lenovo battery-hook strings in target framework
```
+Lcom/android/server/MiuiBatteryServiceStub;
MiuiBatteryServiceStub.java
```

## Decompiled target BatteryService compatibility surface
```smali
1706-
1707-    invoke-virtual {p2, p1}, Ljava/io/PrintWriter;->println(Ljava/lang/String;)V
1708-
1709-    .line 1712
1710:    invoke-static {}, Lcom/android/server/MiuiBatteryServiceStub;->getInstance()Lcom/android/server/MiuiBatteryServiceStub;
1711-
1712-    move-result-object p1
1713-
1714:    invoke-virtual {p1, p2}, Lcom/android/server/MiuiBatteryServiceStub;->dump(Ljava/io/PrintWriter;)V
1715-
1716-    .line 1718
1717-    :goto_25a
1718-    monitor-exit v1
--
5053-
5054-    invoke-virtual {v3}, Landroid/os/Message;->sendToTarget()V
5055-
5056-    .line 1101
5057:    invoke-static {}, Lcom/android/server/MiuiBatteryServiceStub;->getInstance()Lcom/android/server/MiuiBatteryServiceStub;
5058-
5059-    move-result-object v3
5060-
5061-    iget v4, p0, Lcom/android/server/BatteryService;->mPlugType:I
--
5067-    iget-object v6, p0, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;
5068-
5069-    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryTemperatureTenthsCelsius:I
5070-
5071:    invoke-virtual {v3, v4, v5, v6}, Lcom/android/server/MiuiBatteryServiceStub;->setBatteryStatusWithFbo(III)V
5072-
5073-    .line 1103
5074-    return-void
5075-.end method
--
5622-
5623-    if-eqz v0, :cond_3d
5624-
5625-    .line 656
5626:    invoke-static {}, Lcom/android/server/MiuiBatteryServiceStub;->getInstance()Lcom/android/server/MiuiBatteryServiceStub;
5627-
5628-    move-result-object v0
5629-
5630-    iget-object v1, p0, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;
--
5632-    iget v1, v1, Landroid/hardware/health/HealthInfo;->batteryLevel:I
5633-
5634-    int-to-float v1, v1
5635-
5636:    invoke-virtual {v0, v1}, Lcom/android/server/MiuiBatteryServiceStub;->reportLowPowerOff(F)V
5637-
5638-    .line 659
5639-    iget-boolean v0, p0, Lcom/android/server/BatteryService;->mSwitchShutDown:Z
5640-
--
5703-
5704-    if-le v0, v1, :cond_3b
5705-
5706-    .line 693
5707:    invoke-static {}, Lcom/android/server/MiuiBatteryServiceStub;->getInstance()Lcom/android/server/MiuiBatteryServiceStub;
5708-
5709-    move-result-object v0
5710-
5711-    iget-object v1, p0, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;
--
5717-    const/high16 v2, 0x41200000    # 10.0f
5718-
5719-    div-float/2addr v1, v2
5720-
5721:    invoke-virtual {v0, v1}, Lcom/android/server/MiuiBatteryServiceStub;->reportHighTemperaturePowerOff(F)V
5722-
5723-    .line 695
5724-    new-instance v0, Landroid/content/Intent;
5725-
--
6615-
6616-    if-ne p1, v0, :cond_35
6617-
6618-    .line 532
6619:    invoke-static {}, Lcom/android/server/MiuiBatteryServiceStub;->getInstance()Lcom/android/server/MiuiBatteryServiceStub;
6620-
6621-    move-result-object v0
6622-
6623-    iget-object v1, p0, Lcom/android/server/BatteryService;->mContext:Landroid/content/Context;
6624-
6625:    invoke-virtual {v0, v1}, Lcom/android/server/MiuiBatteryServiceStub;->init(Landroid/content/Context;)V
6626-
6627-    .line 535
6628-    :cond_35
6629-    :goto_35
```

### Target `processValuesLocked`
```smali
.method private processValuesLocked(Z)V
    .registers 21
    .param p1, "force"    # Z

    .line 805
    move-object/from16 v1, p0

    const/4 v2, 0x0

    .line 806
    .local v2, "logOutlier":Z
    const-wide/16 v3, 0x0

    .line 809
    .local v3, "dischargeDuration":J
    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v0, v0, Landroid/hardware/health/HealthInfo;->batteryStatus:I

    const/4 v6, 0x1

    if-eq v0, v6, :cond_16

    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v0, v0, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iget v7, v1, Lcom/android/server/BatteryService;->mCriticalBatteryLevel:I

    if-gt v0, v7, :cond_16

    move v0, v6

    goto :goto_17

    :cond_16
    const/4 v0, 0x0

    :goto_17
    iput-boolean v0, v1, Lcom/android/server/BatteryService;->mBatteryLevelCritical:Z

    .line 812
    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    invoke-static {v0}, Lcom/android/server/BatteryService;->plugType(Landroid/hardware/health/HealthInfo;)I

    move-result v0

    iput v0, v1, Lcom/android/server/BatteryService;->mPlugType:I

    .line 823
    :try_start_21
    iget-object v7, v1, Lcom/android/server/BatteryService;->mBatteryStats:Lcom/android/internal/app/IBatteryStats;

    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v8, v0, Landroid/hardware/health/HealthInfo;->batteryStatus:I

    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v9, v0, Landroid/hardware/health/HealthInfo;->batteryHealth:I

    iget v10, v1, Lcom/android/server/BatteryService;->mPlugType:I

    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v11, v0, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v12, v0, Landroid/hardware/health/HealthInfo;->batteryTemperatureTenthsCelsius:I

    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v13, v0, Landroid/hardware/health/HealthInfo;->batteryVoltageMillivolts:I

    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v14, v0, Landroid/hardware/health/HealthInfo;->batteryChargeCounterUah:I

    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v15, v0, Landroid/hardware/health/HealthInfo;->batteryFullChargeUah:I

    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget-wide v5, v0, Landroid/hardware/health/HealthInfo;->batteryChargeTimeToFullNowSeconds:J

    move-wide/from16 v16, v5

    invoke-interface/range {v7 .. v17}, Lcom/android/internal/app/IBatteryStats;->setBatteryState(IIIIIIIIJ)V
    :try_end_4a
    .catch Landroid/os/RemoteException; {:try_start_21 .. :try_end_4a} :catch_4b

    .line 835
    goto :goto_4c

    .line 833
    :catch_4b
    move-exception v0

    .line 837
    :goto_4c
    invoke-direct {v1}, Lcom/android/server/BatteryService;->shutdownIfNoPowerLocked()V

    .line 838
    invoke-direct {v1}, Lcom/android/server/BatteryService;->shutdownIfOverTempLocked()V

    .line 840
    iget-object v0, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v0, v0, Landroid/hardware/health/HealthInfo;->chargingPolicy:I

    invoke-direct {v1, v0}, Lcom/android/server/BatteryService;->translateHalChargingPolicy(I)I

    move-result v0

    .line 842
    .local v0, "translatedChargingPolicy":I
    if-nez p1, :cond_60

    iget v5, v1, Lcom/android/server/BatteryService;->mLastChargingPolicy:I

    if-eq v0, v5, :cond_6c

    .line 843
    :cond_60
    iput v0, v1, Lcom/android/server/BatteryService;->mLastChargingPolicy:I

    .line 844
    iget-object v5, v1, Lcom/android/server/BatteryService;->mHandler:Landroid/os/Handler;

    new-instance v6, Lcom/android/server/BatteryService$$ExternalSyntheticLambda6;

    invoke-direct {v6, v1}, Lcom/android/server/BatteryService$$ExternalSyntheticLambda6;-><init>(Lcom/android/server/BatteryService;)V

    invoke-virtual {v5, v6}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z

    .line 847
    :cond_6c
    if-nez p1, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryStatus:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryStatus:I

    if-ne v5, v6, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryHealth:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryHealth:I

    if-ne v5, v6, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget-boolean v5, v5, Landroid/hardware/health/HealthInfo;->batteryPresent:Z

    iget-boolean v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryPresent:Z

    if-ne v5, v6, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryLevel:I

    if-ne v5, v6, :cond_d2

    iget v5, v1, Lcom/android/server/BatteryService;->mPlugType:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastPlugType:I

    if-ne v5, v6, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryVoltageMillivolts:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryVoltage:I

    if-ne v5, v6, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryTemperatureTenthsCelsius:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryTemperature:I

    if-ne v5, v6, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->maxChargingCurrentMicroamps:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastMaxChargingCurrent:I

    if-ne v5, v6, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->maxChargingVoltageMicrovolts:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastMaxChargingVoltage:I

    if-ne v5, v6, :cond_d2

    iget v5, v1, Lcom/android/server/BatteryService;->mInvalidCharger:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastInvalidCharger:I

    if-ne v5, v6, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryCycleCount:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryCycleCount:I

    if-ne v5, v6, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->chargingState:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastChargingState:I

    if-ne v5, v6, :cond_d2

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryCapacityLevel:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryCapacityLevel:I

    if-eq v5, v6, :cond_3d3

    .line 862
    :cond_d2
    iget v5, v1, Lcom/android/server/BatteryService;->mPlugType:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastPlugType:I

    const-wide/16 v7, 0x0

    if-eq v5, v6, :cond_1a1

    .line 863
    iget v5, v1, Lcom/android/server/BatteryService;->mLastBroadcastPlugType:I

    const/16 v6, 0x58a

    const/16 v9, 0x58d

    const/16 v10, 0x589

    if-nez v5, :cond_147

    .line 865
    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iput v5, v1, Lcom/android/server/BatteryService;->mChargeStartLevel:I

    .line 866
    invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J

    move-result-wide v11

    iput-wide v11, v1, Lcom/android/server/BatteryService;->mChargeStartTime:J

    .line 868
    new-instance v5, Landroid/metrics/LogMaker;

    invoke-direct {v5, v10}, Landroid/metrics/LogMaker;-><init>(I)V

    .line 869
    .local v5, "builder":Landroid/metrics/LogMaker;
    const/4 v10, 0x4

    invoke-virtual {v5, v10}, Landroid/metrics/LogMaker;->setType(I)Landroid/metrics/LogMaker;

    .line 870
    iget v10, v1, Lcom/android/server/BatteryService;->mPlugType:I

    invoke-static {v10}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v10

    invoke-virtual {v5, v9, v10}, Landroid/metrics/LogMaker;->addTaggedData(ILjava/lang/Object;)Landroid/metrics/LogMaker;

    .line 871
    iget-object v9, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v9, v9, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    .line 872
    invoke-static {v9}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v9

    .line 871
    invoke-virtual {v5, v6, v9}, Landroid/metrics/LogMaker;->addTaggedData(ILjava/lang/Object;)Landroid/metrics/LogMaker;

    .line 873
    iget-object v6, v1, Lcom/android/server/BatteryService;->mMetricsLogger:Lcom/android/internal/logging/MetricsLogger;

    invoke-virtual {v6, v5}, Lcom/android/internal/logging/MetricsLogger;->write(Landroid/metrics/LogMaker;)V

    .line 877
    iget-wide v9, v1, Lcom/android/server/BatteryService;->mDischargeStartTime:J

    cmp-long v6, v9, v7

    if-eqz v6, :cond_146

    iget v6, v1, Lcom/android/server/BatteryService;->mDischargeStartLevel:I

    iget-object v9, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v9, v9, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    if-eq v6, v9, :cond_146

    .line 879
    invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J

    move-result-wide v9

    iget-wide v11, v1, Lcom/android/server/BatteryService;->mDischargeStartTime:J

    sub-long v3, v9, v11

    .line 880
    const/4 v2, 0x1

    .line 881
    invoke-static {v3, v4}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v6

    iget v9, v1, Lcom/android/server/BatteryService;->mDischargeStartLevel:I

    .line 882
    invoke-static {v9}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v9

    iget-object v10, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v10, v10, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    invoke-static {v10}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v10

    filled-new-array {v6, v9, v10}, [Ljava/lang/Object;

    move-result-object v6

    .line 881
    const/16 v9, 0xaaa

    invoke-static {v9, v6}, Landroid/util/EventLog;->writeEvent(I[Ljava/lang/Object;)I

    .line 884
    iput-wide v7, v1, Lcom/android/server/BatteryService;->mDischargeStartTime:J

    .line 886
    .end local v5    # "builder":Landroid/metrics/LogMaker;
    :cond_146
    goto :goto_1a1

    :cond_147
    iget v5, v1, Lcom/android/server/BatteryService;->mPlugType:I

    if-nez v5, :cond_146

    .line 888
    invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J

    move-result-wide v11

    iput-wide v11, v1, Lcom/android/server/BatteryService;->mDischargeStartTime:J

    .line 889
    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iput v5, v1, Lcom/android/server/BatteryService;->mDischargeStartLevel:I

    .line 891
    invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J

    move-result-wide v11

    iget-wide v13, v1, Lcom/android/server/BatteryService;->mChargeStartTime:J

    sub-long/2addr v11, v13

    .line 892
    .local v11, "chargeDuration":J
    iget-wide v13, v1, Lcom/android/server/BatteryService;->mChargeStartTime:J

    cmp-long v5, v13, v7

    if-eqz v5, :cond_19f

    cmp-long v5, v11, v7

    if-eqz v5, :cond_19f

    .line 893
    new-instance v5, Landroid/metrics/LogMaker;

    invoke-direct {v5, v10}, Landroid/metrics/LogMaker;-><init>(I)V

    .line 894
    .restart local v5    # "builder":Landroid/metrics/LogMaker;
    const/4 v10, 0x5

    invoke-virtual {v5, v10}, Landroid/metrics/LogMaker;->setType(I)Landroid/metrics/LogMaker;

    .line 895
    iget v10, v1, Lcom/android/server/BatteryService;->mLastBroadcastPlugType:I

    invoke-static {v10}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v10

    invoke-virtual {v5, v9, v10}, Landroid/metrics/LogMaker;->addTaggedData(ILjava/lang/Object;)Landroid/metrics/LogMaker;

    .line 896
    nop

    .line 897
    invoke-static {v11, v12}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v9

    .line 896
    const/16 v10, 0x58c

    invoke-virtual {v5, v10, v9}, Landroid/metrics/LogMaker;->addTaggedData(ILjava/lang/Object;)Landroid/metrics/LogMaker;

    .line 898
    iget v9, v1, Lcom/android/server/BatteryService;->mChargeStartLevel:I

    .line 899
    invoke-static {v9}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v9

    .line 898
    invoke-virtual {v5, v6, v9}, Landroid/metrics/LogMaker;->addTaggedData(ILjava/lang/Object;)Landroid/metrics/LogMaker;

    .line 900
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    .line 901
    invoke-static {v6}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v6

    .line 900
    const/16 v9, 0x58b

    invoke-virtual {v5, v9, v6}, Landroid/metrics/LogMaker;->addTaggedData(ILjava/lang/Object;)Landroid/metrics/LogMaker;

    .line 902
    iget-object v6, v1, Lcom/android/server/BatteryService;->mMetricsLogger:Lcom/android/internal/logging/MetricsLogger;

    invoke-virtual {v6, v5}, Lcom/android/internal/logging/MetricsLogger;->write(Landroid/metrics/LogMaker;)V

    .line 904
    .end local v5    # "builder":Landroid/metrics/LogMaker;
    :cond_19f
    iput-wide v7, v1, Lcom/android/server/BatteryService;->mChargeStartTime:J

    .line 907
    .end local v11    # "chargeDuration":J
    :cond_1a1
    :goto_1a1
    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryStatus:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryStatus:I

    if-ne v5, v6, :cond_1bf

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryHealth:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryHealth:I

    if-ne v5, v6, :cond_1bf

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget-boolean v5, v5, Landroid/hardware/health/HealthInfo;->batteryPresent:Z

    iget-boolean v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryPresent:Z

    if-ne v5, v6, :cond_1bf

    iget v5, v1, Lcom/android/server/BatteryService;->mPlugType:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastPlugType:I

    if-eq v5, v6, :cond_202

    .line 911
    :cond_1bf
    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryStatus:I

    .line 912
    invoke-static {v5}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v5

    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryHealth:I

    invoke-static {v6}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v6

    .line 913
    iget-object v9, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget-boolean v9, v9, Landroid/hardware/health/HealthInfo;->batteryPresent:Z

    invoke-static {v9}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v9

    iget v10, v1, Lcom/android/server/BatteryService;->mPlugType:I

    .line 914
    invoke-static {v10}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v10

    iget-object v11, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget-object v11, v11, Landroid/hardware/health/HealthInfo;->batteryTechnology:Ljava/lang/String;

    filled-new-array {v5, v6, v9, v10, v11}, [Ljava/lang/Object;

    move-result-object v5

    .line 911
    const/16 v6, 0xaa3

    invoke-static {v6, v5}, Landroid/util/EventLog;->writeEvent(I[Ljava/lang/Object;)I

    .line 915
    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryStatus:I

    .line 917
    invoke-static {v5}, Ljava/lang/Integer;->toString(I)Ljava/lang/String;

    move-result-object v5

    .line 915
    const-string v6, "debug.tracing.battery_status"

    invoke-static {v6, v5}, Landroid/os/SystemProperties;->set(Ljava/lang/String;Ljava/lang/String;)V

    .line 918
    iget v5, v1, Lcom/android/server/BatteryService;->mPlugType:I

    invoke-static {v5}, Ljava/lang/Integer;->toString(I)Ljava/lang/String;

    move-result-object v5

    const-string v6, "debug.tracing.plug_type"

    invoke-static {v6, v5}, Landroid/os/SystemProperties;->set(Ljava/lang/String;Ljava/lang/String;)V

    .line 920
    :cond_202
    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryLevel:I

    if-eq v5, v6, :cond_22b

    .line 923
    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    .line 925
    invoke-static {v5}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v5

    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryVoltageMillivolts:I

    .line 926
    invoke-static {v6}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v6

    iget-object v9, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v9, v9, Landroid/hardware/health/HealthInfo;->batteryTemperatureTenthsCelsius:I

    .line 927
    invoke-static {v9}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v9

    filled-new-array {v5, v6, v9}, [Ljava/lang/Object;

    move-result-object v5

    .line 923
    const/16 v6, 0xaa2

    invoke-static {v6, v5}, Landroid/util/EventLog;->writeEvent(I[Ljava/lang/Object;)I

    .line 929
    :cond_22b
    iget-boolean v5, v1, Lcom/android/server/BatteryService;->mBatteryLevelCritical:Z

    if-eqz v5, :cond_240

    iget-boolean v5, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryLevelCritical:Z

    if-nez v5, :cond_240

    iget v5, v1, Lcom/android/server/BatteryService;->mPlugType:I

    if-nez v5, :cond_240

    .line 933
    invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J

    move-result-wide v5

    iget-wide v9, v1, Lcom/android/server/BatteryService;->mDischargeStartTime:J

    sub-long/2addr v5, v9

    .line 934
    .end local v3    # "dischargeDuration":J
    .local v5, "dischargeDuration":J
    const/4 v2, 0x1

    move-wide v3, v5

    .line 937
    .end local v5    # "dischargeDuration":J
    .restart local v3    # "dischargeDuration":J
    :cond_240
    iget-boolean v5, v1, Lcom/android/server/BatteryService;->mBatteryLevelLow:Z

    .line 947
    iget v6, v1, Lcom/android/server/BatteryService;->mPlugType:I

    .line 937
    if-nez v5, :cond_25a

    .line 939
    if-nez v6, :cond_278

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryStatus:I

    const/4 v6, 0x1

    if-eq v5, v6, :cond_278

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iget v9, v1, Lcom/android/server/BatteryService;->mLowBatteryWarningLevel:I

    if-gt v5, v9, :cond_278

    .line 943
    iput-boolean v6, v1, Lcom/android/server/BatteryService;->mBatteryLevelLow:Z

    goto :goto_278

    .line 947
    :cond_25a
    if-eqz v6, :cond_260

    .line 948
    const/4 v5, 0x0

    iput-boolean v5, v1, Lcom/android/server/BatteryService;->mBatteryLevelLow:Z

    goto :goto_278

    .line 949
    :cond_260
    const/4 v5, 0x0

    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iget v9, v1, Lcom/android/server/BatteryService;->mLowBatteryCloseWarningLevel:I

    if-lt v6, v9, :cond_26c

    .line 950
    iput-boolean v5, v1, Lcom/android/server/BatteryService;->mBatteryLevelLow:Z

    goto :goto_278

    .line 951
    :cond_26c
    if-eqz p1, :cond_278

    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iget v9, v1, Lcom/android/server/BatteryService;->mLowBatteryWarningLevel:I

    if-lt v6, v9, :cond_278

    .line 954
    iput-boolean v5, v1, Lcom/android/server/BatteryService;->mBatteryLevelLow:Z

    .line 958
    :cond_278
    :goto_278
    iget v5, v1, Lcom/android/server/BatteryService;->mSequence:I

    const/16 v18, 0x1

    add-int/lit8 v5, v5, 0x1

    iput v5, v1, Lcom/android/server/BatteryService;->mSequence:I

    .line 963
    iget v5, v1, Lcom/android/server/BatteryService;->mPlugType:I

    const/4 v6, 0x2

    const-string/jumbo v9, "seq"

    const/high16 v10, 0x4000000

    if-eqz v5, :cond_2b6

    iget v5, v1, Lcom/android/server/BatteryService;->mLastBroadcastPlugType:I

    if-nez v5, :cond_2b6

    .line 964
    new-instance v5, Landroid/content/Intent;

    const-string v11, "android.intent.action.ACTION_POWER_CONNECTED"

    invoke-direct {v5, v11}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    .line 965
    .local v5, "statusIntent":Landroid/content/Intent;
    invoke-virtual {v5, v10}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    .line 966
    iget v11, v1, Lcom/android/server/BatteryService;->mSequence:I

    invoke-virtual {v5, v9, v11}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;

    .line 967
    iget-object v11, v1, Lcom/android/server/BatteryService;->mHandler:Landroid/os/Handler;

    invoke-virtual {v11, v6}, Landroid/os/Handler;->removeMessages(I)V

    .line 968
    invoke-static {}, Lcom/android/internal/os/SomeArgs;->obtain()Lcom/android/internal/os/SomeArgs;

    move-result-object v11

    .line 969
    .local v11, "args":Lcom/android/internal/os/SomeArgs;
    iget-object v12, v1, Lcom/android/server/BatteryService;->mContext:Landroid/content/Context;

    iput-object v12, v11, Lcom/android/internal/os/SomeArgs;->arg1:Ljava/lang/Object;

    .line 970
    iput-object v5, v11, Lcom/android/internal/os/SomeArgs;->arg2:Ljava/lang/Object;

    .line 971
    iget-object v12, v1, Lcom/android/server/BatteryService;->mHandler:Landroid/os/Handler;

    invoke-virtual {v12, v6, v11}, Landroid/os/Handler;->obtainMessage(ILjava/lang/Object;)Landroid/os/Message;

    move-result-object v6

    .line 972
    invoke-virtual {v6}, Landroid/os/Message;->sendToTarget()V

    .end local v5    # "statusIntent":Landroid/content/Intent;
    .end local v11    # "args":Lcom/android/internal/os/SomeArgs;
    goto :goto_2e6

    .line 973
    :cond_2b6
    iget v5, v1, Lcom/android/server/BatteryService;->mPlugType:I

    if-nez v5, :cond_2e6

    iget v5, v1, Lcom/android/server/BatteryService;->mLastBroadcastPlugType:I

    if-eqz v5, :cond_2e6

    .line 974
    new-instance v5, Landroid/content/Intent;

    const-string v11, "android.intent.action.ACTION_POWER_DISCONNECTED"

    invoke-direct {v5, v11}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    .line 975
    .restart local v5    # "statusIntent":Landroid/content/Intent;
    invoke-virtual {v5, v10}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    .line 976
    iget v11, v1, Lcom/android/server/BatteryService;->mSequence:I

    invoke-virtual {v5, v9, v11}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;

    .line 977
    iget-object v11, v1, Lcom/android/server/BatteryService;->mHandler:Landroid/os/Handler;

    invoke-virtual {v11, v6}, Landroid/os/Handler;->removeMessages(I)V

    .line 978
    invoke-static {}, Lcom/android/internal/os/SomeArgs;->obtain()Lcom/android/internal/os/SomeArgs;

    move-result-object v11

    .line 979
    .restart local v11    # "args":Lcom/android/internal/os/SomeArgs;
    iget-object v12, v1, Lcom/android/server/BatteryService;->mContext:Landroid/content/Context;

    iput-object v12, v11, Lcom/android/internal/os/SomeArgs;->arg1:Ljava/lang/Object;

    .line 980
    iput-object v5, v11, Lcom/android/internal/os/SomeArgs;->arg2:Ljava/lang/Object;

    .line 981
    iget-object v12, v1, Lcom/android/server/BatteryService;->mHandler:Landroid/os/Handler;

    invoke-virtual {v12, v6, v11}, Landroid/os/Handler;->obtainMessage(ILjava/lang/Object;)Landroid/os/Message;

    move-result-object v6

    .line 982
    invoke-virtual {v6}, Landroid/os/Message;->sendToTarget()V

    goto :goto_2e7

    .line 973
    .end local v5    # "statusIntent":Landroid/content/Intent;
    .end local v11    # "args":Lcom/android/internal/os/SomeArgs;
    :cond_2e6
    :goto_2e6
    nop

    .line 985
    :goto_2e7
    invoke-direct {v1}, Lcom/android/server/BatteryService;->shouldSendBatteryLowLocked()Z

    move-result v5

    const/4 v6, 0x3

    if-eqz v5, :cond_319

    .line 986
    const/4 v5, 0x1

    iput-boolean v5, v1, Lcom/android/server/BatteryService;->mSentLowBatteryBroadcast:Z

    .line 987
    new-instance v5, Landroid/content/Intent;

    const-string v11, "android.intent.action.BATTERY_LOW"

    invoke-direct {v5, v11}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    .line 988
    .restart local v5    # "statusIntent":Landroid/content/Intent;
    invoke-virtual {v5, v10}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    .line 989
    iget v10, v1, Lcom/android/server/BatteryService;->mSequence:I

    invoke-virtual {v5, v9, v10}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;

    .line 990
    iget-object v9, v1, Lcom/android/server/BatteryService;->mHandler:Landroid/os/Handler;

    invoke-virtual {v9, v6}, Landroid/os/Handler;->removeMessages(I)V

    .line 991
    invoke-static {}, Lcom/android/internal/os/SomeArgs;->obtain()Lcom/android/internal/os/SomeArgs;

    move-result-object v9

    .line 992
    .local v9, "args":Lcom/android/internal/os/SomeArgs;
    iget-object v10, v1, Lcom/android/server/BatteryService;->mContext:Landroid/content/Context;

    iput-object v10, v9, Lcom/android/internal/os/SomeArgs;->arg1:Ljava/lang/Object;

    .line 993
    iput-object v5, v9, Lcom/android/internal/os/SomeArgs;->arg2:Ljava/lang/Object;

    .line 994
    iget-object v10, v1, Lcom/android/server/BatteryService;->mHandler:Landroid/os/Handler;

    invoke-virtual {v10, v6, v9}, Landroid/os/Handler;->obtainMessage(ILjava/lang/Object;)Landroid/os/Message;

    move-result-object v6

    .line 995
    invoke-virtual {v6}, Landroid/os/Message;->sendToTarget()V

    .end local v5    # "statusIntent":Landroid/content/Intent;
    .end local v9    # "args":Lcom/android/internal/os/SomeArgs;
    goto :goto_350

    .line 996
    :cond_319
    iget-boolean v5, v1, Lcom/android/server/BatteryService;->mSentLowBatteryBroadcast:Z

    if-eqz v5, :cond_350

    iget-object v5, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v5, v5, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iget v11, v1, Lcom/android/server/BatteryService;->mLowBatteryCloseWarningLevel:I

    if-lt v5, v11, :cond_350

    .line 998
    const/4 v5, 0x0

    iput-boolean v5, v1, Lcom/android/server/BatteryService;->mSentLowBatteryBroadcast:Z

    .line 999
    new-instance v5, Landroid/content/Intent;

    const-string v11, "android.intent.action.BATTERY_OKAY"

    invoke-direct {v5, v11}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    .line 1000
    .restart local v5    # "statusIntent":Landroid/content/Intent;
    invoke-virtual {v5, v10}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    .line 1001
    iget v10, v1, Lcom/android/server/BatteryService;->mSequence:I

    invoke-virtual {v5, v9, v10}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;

    .line 1002
    iget-object v9, v1, Lcom/android/server/BatteryService;->mHandler:Landroid/os/Handler;

    invoke-virtual {v9, v6}, Landroid/os/Handler;->removeMessages(I)V

    .line 1003
    invoke-static {}, Lcom/android/internal/os/SomeArgs;->obtain()Lcom/android/internal/os/SomeArgs;

    move-result-object v9

    .line 1004
    .restart local v9    # "args":Lcom/android/internal/os/SomeArgs;
    iget-object v10, v1, Lcom/android/server/BatteryService;->mContext:Landroid/content/Context;

    iput-object v10, v9, Lcom/android/internal/os/SomeArgs;->arg1:Ljava/lang/Object;

    .line 1005
    iput-object v5, v9, Lcom/android/internal/os/SomeArgs;->arg2:Ljava/lang/Object;

    .line 1006
    iget-object v10, v1, Lcom/android/server/BatteryService;->mHandler:Landroid/os/Handler;

    invoke-virtual {v10, v6, v9}, Landroid/os/Handler;->obtainMessage(ILjava/lang/Object;)Landroid/os/Message;

    move-result-object v6

    .line 1007
    invoke-virtual {v6}, Landroid/os/Message;->sendToTarget()V

    goto :goto_351

    .line 996
    .end local v5    # "statusIntent":Landroid/content/Intent;
    .end local v9    # "args":Lcom/android/internal/os/SomeArgs;
    :cond_350
    :goto_350
    nop

    .line 1014
    :goto_351
    invoke-direct/range {p0 .. p1}, Lcom/android/server/BatteryService;->rateLimitBatteryChangedBroadcast(Z)Z

    move-result v5

    .line 1016
    .local v5, "rateLimitBatteryChangedBroadcast":Z
    if-nez v5, :cond_35a

    .line 1017
    invoke-direct/range {p0 .. p1}, Lcom/android/server/BatteryService;->sendBatteryChangedIntentLocked(Z)V

    .line 1019
    :cond_35a
    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryLevel:I

    iget-object v9, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v9, v9, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    if-ne v6, v9, :cond_368

    iget v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastPlugType:I

    iget v9, v1, Lcom/android/server/BatteryService;->mPlugType:I

    if-eq v6, v9, :cond_36b

    .line 1021
    :cond_368
    invoke-direct {v1}, Lcom/android/server/BatteryService;->sendBatteryLevelChangedIntentLocked()V

    .line 1028
    :cond_36b
    sget-boolean v6, Landroid/os/Build;->IS_MIUI:Z

    if-eqz v6, :cond_374

    .line 1029
    iget-object v6, v1, Lcom/android/server/BatteryService;->mLed:Lcom/android/server/BatteryService$Led;

    invoke-virtual {v6}, Lcom/android/server/BatteryService$Led;->updateLightsLocked()V

    .line 1033
    :cond_374
    if-eqz v2, :cond_37d

    cmp-long v6, v3, v7

    if-eqz v6, :cond_37d

    .line 1034
    invoke-direct {v1, v3, v4}, Lcom/android/server/BatteryService;->logOutlierLocked(J)V

    .line 1038
    :cond_37d
    if-nez v5, :cond_3d3

    .line 1039
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryStatus:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryStatus:I

    .line 1040
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryHealth:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryHealth:I

    .line 1041
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget-boolean v6, v6, Landroid/hardware/health/HealthInfo;->batteryPresent:Z

    iput-boolean v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryPresent:Z

    .line 1042
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryLevel:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryLevel:I

    .line 1043
    iget v6, v1, Lcom/android/server/BatteryService;->mPlugType:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastPlugType:I

    .line 1044
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryVoltageMillivolts:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryVoltage:I

    .line 1045
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryTemperatureTenthsCelsius:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryTemperature:I

    .line 1046
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->maxChargingCurrentMicroamps:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastMaxChargingCurrent:I

    .line 1047
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->maxChargingVoltageMicrovolts:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastMaxChargingVoltage:I

    .line 1048
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryChargeCounterUah:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastChargeCounter:I

    .line 1049
    iget-boolean v6, v1, Lcom/android/server/BatteryService;->mBatteryLevelCritical:Z

    iput-boolean v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryLevelCritical:Z

    .line 1050
    iget v6, v1, Lcom/android/server/BatteryService;->mInvalidCharger:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastInvalidCharger:I

    .line 1051
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryCycleCount:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryCycleCount:I

    .line 1052
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->chargingState:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastChargingState:I

    .line 1053
    iget-object v6, v1, Lcom/android/server/BatteryService;->mHealthInfo:Landroid/hardware/health/HealthInfo;

    iget v6, v6, Landroid/hardware/health/HealthInfo;->batteryCapacityLevel:I

    iput v6, v1, Lcom/android/server/BatteryService;->mLastBroadcastBatteryCapacityLevel:I

    .line 1056
    .end local v5    # "rateLimitBatteryChangedBroadcast":Z
    :cond_3d3
    return-void
.end method
.method private processValuesLocked(ZLjava/io/PrintWriter;)V
    .registers 4
    .param p1, "forceUpdate"    # Z
    .param p2, "pw"    # Ljava/io/PrintWriter;

    .line 1672
    invoke-direct {p0, p1}, Lcom/android/server/BatteryService;->processValuesLocked(Z)V

    .line 1673
    if-eqz p2, :cond_c

    if-eqz p1, :cond_c

    .line 1674
    iget v0, p0, Lcom/android/server/BatteryService;->mSequence:I

    invoke-virtual {p2, v0}, Ljava/io/PrintWriter;->println(I)V

    .line 1676
    :cond_c
    return-void
.end method
```
