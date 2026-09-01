# UAV Autotune V5.4.1 代码清理报告

日期：2026-08-30  
工程：`UAV_Autotune_v5_4_1_Validation_Fix`  
结论：**代码结构清理完成；静态回归通过；MATLAB/Simulink、WSL 与 Native SITL 动态回归未运行。**

## 1. 审计结论

清理前工程同时存在 V4.x、V5.1、V5.2、V5.3、V5.4 和 V5.4.1 的入口、包目录、桥接器、优化器、候选参数和结果目录，且正式 V5.4.1 链仍跨 `+v52`、`+v53`、`+v54` 调用。配置中同时存在默认 Level 6 与正式 runner 默认 Level 2；命令链还保留 `desired_internal_attitude` 兼容语义；模型飞控 S-function 同时包含 ArduPilot SITL 和一套独立的 MATLAB PID/TECS 近似控制器。

清理后：

- 根目录公共入口只有 `start_autotune.m`；初始化只有 `setup_project.m`。
- 正式编排统一到 `matlab/+uav`，不再通过版本包调用。
- 正式场景只允许 Roll/Pitch 的 `rc_normalized`。
- 飞控后端只允许 `ardupilot_sitl`，另保留明确标注的 plant-only `test_direct_actuator`。
- 模型内旧 PID/TECS/MIL 控制器和 direct-attitude 分支已经删除。
- 配置版本统一为 5.4.1，默认 `AUTOTUNE_LEVEL` 统一为 2。
- 唯一模型为 `model/UAV_Autotune_Model_4Axis.slx`。
- 旧版本与无效结果不再位于正式源码/结果路径。

本次工作没有开发新调参算法，也没有改变历史 trial 的 PASS/FAIL。

## 2. 当前唯一入口

```matlab
setup_project
result = start_autotune(action, Name=Value)
```

支持的 action：

| Action | 作用 | 正式 Native 调参 |
|---|---|---|
| `physical_validation` | Roll/Pitch/Yaw 被控对象物理能力 | 否 |
| `level_screen` | AUTOTUNE_LEVEL 工程能力筛选 | 否 |
| `axis` | 单次 Roll 或 Pitch Native AUTOTUNE | 是 |
| `repeatability` | Roll/Pitch 独立重复性 campaign | 是 |
| `report` | 从现有证据生成 V5.4.1 汇总 | 否 |
| `regression` | 运行清理后的回归套件 | 否 |

Yaw 不接受 `axis` Native AUTOTUNE；当前 baseline 的 `YAW_RATE_ENABLE=0`，Yaw 只在 plant-only 物理能力验证中出现。

## 3. 当前真实调用链

```text
start_autotune
  -> setup_project
  -> uav.runAutotuneRepeatability / uav.runNativeAutotuneAxis
  -> uav.generateExcitation
  -> uav.runScenario
     -> uav.loadConfiguration
     -> uav.configureRun
     -> uav.writeDefaults / validateParameterSet
     -> scripts/sitl/start_sitl_wsl.ps1
     -> scripts/sitl/start_mode_session_wsl.ps1
     -> ArduPlane Plane-4.7.0 @ 1511f27194f1dcc3728270883047bdf022b3fd53
     <-> model/ArduPilotJSONBridge.m
     <-> model/UAV_Autotune_Model_4Axis.slx
     -> stop_sitl / export_dataflash
     -> mode, packet, safety, DataFlash, ATRP, parameter readback gates
  -> uav.parseNativeAutotuneLog
  -> uav.collectFinalAutotuneParameters
```

执行语义为：Simulink 发送归一化 RC，ArduPlane 生成内部目标、控制输出和 AUTOTUNE 参数。活动代码中没有 direct-attitude 或 direct-body-rate 正式入口。

## 4. 迁移与合并

### 4.1 包函数迁移

| 原位置 | 当前位置 |
|---|---|
| `+v52/applyParamFile` | `+uav/applyParamFile` |
| `+v52/exportDataFlash` | `+uav/exportDataFlash` |
| `+v52/invokePowerShell` | `+uav/invokePowerShell` |
| `+v52/loadConfiguration` | `+uav/loadConfiguration` |
| `+v52/loadParameterMetadata` | `+uav/loadParameterMetadata` |
| `+v52/validateParameterSet` | `+uav/validateParameterSet` |
| `+v52/writeSimulationData` | `+uav/writeSimulationData` |
| `+v53/configureRun` | `+uav/configureRun` |
| `+v53/evaluateSafetyEnvelope` | `+uav/evaluateSafetyEnvelope` |
| `+v53/runScenario` | `+uav/runScenario` |
| `+v53/startModeSession`, `waitModeSession` | `+uav/startModeSession`, `waitModeSession` |
| `+v53` 参数读写/合并/回读函数 | 同名迁移到 `+uav` |
| `+v54/autotuneLevelTable` | `+uav/autotuneLevelTable` |
| `+v54/sensorParameterOverrides` | `+uav/sensorParameterOverrides` |

### 4.2 V5.4.1 runner 统一命名

| 原文件 | 当前文件 |
|---|---|
| `run_v541_autotune_repeatability.m` | `+uav/runAutotuneRepeatability.m` |
| `run_v541_native_autotune_axis.m` | `+uav/runNativeAutotuneAxis.m` |
| `run_v541_physical_control_authority.m` | `+uav/runPhysicalControlAuthority.m` |
| `generate_native_autotune_excitation.m` | `+uav/generateExcitation.m` |
| `parse_native_autotune_log.m` | `+uav/parseNativeAutotuneLog.m` |
| `generate_autotune_level_feasibility_v541.m` | `+uav/generateLevelFeasibility.m` |
| `generate_v541_validation_fix_report.m` | `+uav/generateValidationReport.m` |
| `calculate_step_overshoot.m` | `+uav/calculateStepOvershoot.m` |

### 4.3 模型 helper 统一命名

`create_v52_buses`、`v54_actuator_*`、`v54_deterministic_gaussian`、`v54_direct_actuator_pwm`、`v54_servo_channels`、`v541_surface_targets`、`load_v54_*` 和 `write_ardupilot_sitl_defaults_v52` 已改为无版本前缀的当前名称。

`V52ArduPilotJSONBridge` 已统一为 `ArduPilotJSONBridge`，运行字段由 `P.v52/P.v53` 改为 `P.interface/P.session`。

## 5. 关键逻辑清理

### 5.1 direct-attitude 移除

- `loadConfiguration` 只接受 `command_semantics="rc_normalized"`。
- `uav_command_sfunc` 只生成 Roll/Pitch normalized RC。
- `ArduPilotJSONBridge.commandToRC` 不再将姿态角换算为 RC。
- `generateExcitation` 不再生成 `desired_internal_*` 字段。
- 活动场景目录只保留 `native_roll_autotune.json` 与 `native_pitch_autotune.json`。

保留的历史 campaign 中 `scenario.json` 是原运行证据，未篡改，可能仍含旧审计字段；它们不被当前代码加载。

### 5.2 模型内控制器移除

`uav_autopilot_sfunc` 中旧 Roll/Pitch/Yaw/TECS PID、积分器、滤波器、heading surrogate 和 `mil` backend 已全部移除。未知 backend 现在是硬错误。

### 5.3 参数冲突收口

- `config/project.json`：版本 `5.4.1`，默认 Level 2。
- `config/autotune/baseline.param`：`AUTOTUNE_LEVEL,2`。
- `start_autotune` 与 repeatability runner：默认 Level 2。
- `configureRun` 直接读取唯一 baseline，不再读取 `Rank1_Candidate_C.param`。
- `applyParamFile` 只把 baseline 中模型已知的 `P.ap` 字段应用到被控对象配置；完整固件字段仍在 defaults 合并/元数据验证阶段处理。

## 6. 已删除的文件

### 6.1 根目录旧入口与报告器

删除：

`check_environment.m`、`evaluate_attitude_benchmark.m`、`finalize_run.m`、`generate_control_authority_envelope.m`、`generate_v53_final_report.m`、`generate_v54_final_comparison.m`、`generate_v54_final_report.m`、`measure_pitch_control_authority.m`、`measure_roll_control_authority.m`、`measure_yaw_control_authority.m`、`recover_native_autotune_run.m`、`recover_v54_post_completion_tail_abort.m`、`resume_v54_candidate_after_recovered_roll.m`、`run_ardupilot_autotune_level_sweep.m`、`run_interface_acceptance.m`、`run_native_autotune.m`、`run_native_pitch_autotune.m`、`run_native_roll_autotune.m`、`run_repeatability_test.m`、`run_roll_autotune_baseline.m`、`run_smoke_test.m`、`run_speedup_test.m`、`run_trial_repeatability.m`、全部 `run_v53_*`、全部 `run_v54_*`、`runScenario.m`、`start_sitl.m`、`start_v53_native_autotune.m`、`stop_sitl.m`。

### 6.2 旧优化/验证模型代码

删除：

`aircraft_result_identity.m`、`ardupilot_param_map.m`、`autotune_cruise_range_objective.m`、`autotune_objective.m`、`autotune_objective_v31.m`、`autotune_quality_gate.m`、`autotune_quality_gate_v31.m`、`autotune_quality_report.m`、`autotune_speed_continuity_gate.m`、`complete_v4_2_candidate_pool.m`、`export_cruise_range_candidates.m`、`export_mission_planner_params.m`、`finalize_uav_a_v4_3.m`、`gain_group_definition.m`、`generate_uav_a_v4_3_final_analysis.m`、`generate_v4_2_final_report.m`、`init_uav_model.m`、全部旧 `plot_*`、`rebind_aircraft_runtime_paths.m`、`recheck_v4_2_continuity.m`、`rerank_v4_3_candidates.m`、`result_reuse_allowed.m`、全部 V4 resume/pipeline/cruise/gust/screen 函数、`run_nominal_sim.m`、`run_pid_autotune.m`、`safe_clear_aircraft_outputs.m`、`set_gain_group.m`、`setup_this_computer.m`、`START_HERE.m`、`start_uav_autotune.m`、`uav_cruise_case.m`、`v4_2_seed_parameters.m`、`V51ArduPilotJSONBridge.m`、旧 `validate_*`/`verify_*`、`write_ardupilot_sitl_defaults_v51.m`、`resolve_local_machine_paths.m`。

同时删除 `+uav/recommendAutotuneLevel.m`，因为它仍读取 V5.4 旧能力结果，与当前 `generateLevelFeasibility` 重复且冲突。

### 6.3 重复配置与旧场景

删除：

- `config/ardupilot/Rank1_Candidate_C.param`。
- 除 `baseline.param` 外的 12 个历史 Native candidate/selected 参数文件。
- `config/optimization/roll_fbwa_v1.*`。
- `auto_waypoint_turn`、`direct_attitude_test`、旧 FBWA/FBWB/GUIDED、V5.3 benchmark 等 13 个非正式场景。

### 6.4 旧工具

删除旧 `tools/` 中的 mode change、Mission Planner 导出/验证、Windows compatibility、V5.1 校验和 V5.3 manifest 脚本；删除旧根 `wsl/` 中的 `native_autotune_mode.py`、Mission Planner tlog 验证脚本和旧发行版配置。

## 7. 已隔离的目录/文件

由于工程没有 Git 恢复点，系统拒绝直接递归删除大目录。以下对象被安全移动到 `results/code_cleanup/_quarantine/`，不在 MATLAB 路径或正式结果链中：

- 旧包：`+v51`、`+v52`、`+v53`、`+v54`。
- 旧结果：`results/aircraft`、`results/v5_0`…`v5_4`。
- 两个有 `INVALIDATED.json` 的旧 repeatability/campaign 及 completion 汇总。
- stability、alignment、quaternion、gyro 四个一次性 probe campaign。
- 原工程 `.7z` 备份包。
- 最新保留 campaign 内的 `simulink_cache`、`simulink_codegen` 和 PID 标记。
- 已清空的旧 `tools`、根 `wsl`、旧配置目录与空结果目录。

隔离区共 1023 个文件、约 87.79 MB。确认外部备份后可人工删除。

## 8. 保留的正式结果

保留的最新 repeatability campaign：`20260825_184700_426_repeatability_level2`。

| 轴 | 完成 | 重复性 | 原始结论 |
|---|---:|---|---|
| Roll | 3/3 | PASS | 三次均 `COMPLETE_OFFICIAL_FINISHED` |
| Pitch | 0/3 | FAIL | 三次均 `INCOMPLETE_TIMEOUT` |
| Overall | — | FAIL | Roll/Pitch 未同时通过 |

该结论未被本次代码整理修改。物理控制能力、Level 筛选和验证结果分别保留在 `results/v5_4_1/` 的对应目录。

## 9. 回归结果

| 检查 | 状态 | 说明 |
|---|---|---|
| 活动 JSON 解析 | PASS | 7 个当前配置文件全部可解析 |
| PowerShell 语法 | PASS | 11 个脚本通过语言解析器 |
| Python AST | PASS | 2 个 Python 脚本可解析 |
| MATLAB 文件/函数名 | PASS | 主函数名与文件名一致 |
| `uav.*` 引用解析 | PASS | 所有包引用均有对应函数 |
| 活动旧引用扫描 | PASS | 无旧 package、MIL backend、direct-attitude 引用 |
| SLX 静态引用 | PASS | 7 个 S-function 均存在，无旧 bridge/helper 引用 |
| SITL 脚本根目录解析 | PASS | 正确解析当前根、版本 5.4.1、Level 2 |
| 预期文件清单 | PASS | 入口、模型、场景、脚本、测试、文档和报告均存在 |
| 根目录入口整洁性 | PASS | 根目录 MATLAB 文件仅剩两个入口 |
| 文档命令扫描 | PASS | 用户文档无旧 tools 路径或旧 runner 命令 |
| MATLAB Code Analyzer | NOT_RUN | 无法连接本地 MATLAB 会话 |
| MATLAB 回归套件 | NOT_RUN | 无法连接本地 MATLAB 会话 |
| Simulink load/update | NOT_RUN | 无法连接本地 MATLAB 会话 |
| 执行机构/传感器仿真 | NOT_RUN | 无法连接本地 MATLAB 会话 |
| WSL shell syntax | NOT_RUN | 本机 WSL 调用未进入 bash |
| Native SITL smoke | NOT_RUN | MATLAB/WSL 环境不可用，未启动 |

机器可读表：`results/code_cleanup/REGRESSION_RESULTS.csv`。

## 10. 剩余风险与后续验证

1. 必须在可连接 MATLAB 的环境执行 `start_autotune("regression")`；在此之前不能宣称 Simulink update 或仿真回归 PASS。
2. 必须恢复可用 WSL 后运行环境报告，并至少做一次低成本 Roll Native smoke；未运行项不得改写为 PASS。
3. Pitch 最新正式证据仍是 0/3 完成，本次整理没有修复或掩盖该问题。
4. 右副翼、升降舵、方向舵仍含由左副翼曲线推定的数据来源，飞行前需要硬件台架确认。
5. `results/code_cleanup/_quarantine` 只是可恢复隔离，不是最终物理删除。

## 11. 建议复验顺序

```matlab
setup_project
start_autotune("regression")
start_autotune("physical_validation", Axis="all")
start_autotune("level_screen")
start_autotune("axis", Axis="roll", Level=2)
```

只有上述回归和 smoke 真实通过后，才考虑新的完整 repeatability campaign；不得复用或覆盖历史目录。
