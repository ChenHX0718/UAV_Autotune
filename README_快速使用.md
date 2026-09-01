# UAV Autotune 快速使用

> 适用版本：**5.4.1-Validation-Fix**  
> 目标读者：第一次接触本工程、需要在新电脑上跑通仿真，或需要替换成一架新固定翼飞机的人。  
> 本文只回答四件事：  
> **① 怎么把工程跑起来；② 新飞机到底改哪里；③ 哪些参数必须改、是什么意思；④ 怎么开始 AUTOTUNE 并找到最终结果。**  
> 原理、模块、信号链、代码职责和 Gate 细节见 `README_详细说明.md`。

---

## 0. 先看这一页：第一次使用到底要做什么

如果你只是想用工程里当前已经配置好的飞机验证流程，按下面顺序执行：

```matlab
setup_project;

E = check_environment;

G = run_v53_interface_regression;
assert(G.overall == "PASS");

C = run_v541_physical_control_authority;

F = generate_autotune_level_feasibility_v541;

R = run_v541_autotune_repeatability( ...
    Level=2, ...
    Count=3, ...
    RollCycles=30, ...
    PitchCycles=20, ...
    ActuatorFidelity="ENGINEERING", ...
    SensorFidelity="ENGINEERING", ...
    RandomSeed=42);

generate_v541_validation_fix_report;
```

最终报告从这里看：

```text
results/v5_4_1/RESULT.md
```

当前版本的已知正式状态是：

- Roll Level 2 重复性：**3/3 通过**
- Pitch：**0/3 在 180 s 内得到官方 `Pitch: Finished`**
- 因此当前工程的整体结论仍是：**验证未完成**
- 当前结果**不能直接作为实飞放行或最终参数推荐**

如果你要换一架新飞机，不要直接改一个质量、一个翼展就跑 AUTOTUNE。请按本文第 4～8 节做。

---

# 1. 这个工程到底是什么

这个工程不是“MATLAB 自己搜索一组 PID”。

它的结构是：

```text
MATLAB / Simulink
        │
        │  UDP / JSON-FDM
        ▼
ArduPilot ArduPlane SITL
```

三部分职责非常明确：

### Simulink
是**唯一飞机 Truth Model（真实飞机模型）**，负责：

- 执行机构
- 气动力
- 推进
- 环境
- 传感器边界
- 6DOF 刚体运动

### ArduPilot ArduPlane SITL
运行真实 ArduPlane 飞控代码，负责：

- RC 输入与标定
- FBWA
- 姿态/角速度控制
- 舵机输出
- Native AUTOTUNE
- FF/P/I/D 参数更新

### MATLAB
负责：

- 读取工程配置
- 启动与停止 WSL/SITL
- 启动 Simulink
- 交换 UDP/JSON 数据
- 生成测试激励
- 读取 ArduPilot 参数
- 解析 DataFlash
- 运行 Gate
- 保存结果和报告

**Native AUTOTUNE 的 FF/P/I/D 搜索发生在 ArduPilot 内部，不是 MATLAB 替它优化。**

---

# 2. 新电脑第一次部署

## 2.1 Windows / WSL 环境

当前工程验证过的环境为：

| 项目 | 当前验证环境 |
|---|---|
| Windows | Windows 10 22H2，build 19045 |
| WSL | WSL2 |
| Linux | Ubuntu 24.04 LTS，发行版名 `Ubuntu-24.04` |
| MATLAB | R2024b / 24.2 |
| Python | 3.12.3 |
| ArduPlane | `Plane-4.7.0` |
| ArduPilot commit | `1511f27194f1dcc3728270883047bdf022b3fd53` |
| build target | `sitl/plane` |
| SITL binary | `build/sitl/bin/arduplane` |

管理员 PowerShell：

```powershell
wsl --install -d Ubuntu-24.04
```

检查：

```powershell
wsl -l -v
```

必须看到 `Ubuntu-24.04`，并且 `VERSION` 为 `2`。

---

## 2.2 在工程根目录执行 WSL/ArduPilot 初始化

PowerShell：

```powershell
.\tools\setup_wsl_ardupilot.ps1 -Distro Ubuntu-24.04
```

然后：

```powershell
.\tools\build_ardupilot_wsl.ps1 -Distro Ubuntu-24.04
```

最后生成环境报告：

```powershell
.\tools\report_wsl_environment.ps1 -Distro Ubuntu-24.04
```

这一步的目标不是“飞机飞起来”，而是确认：

1. WSL 可用；
2. Ubuntu 版本正确；
3. ArduPilot 源码/版本正确；
4. `arduplane` 可以构建；
5. MATLAB 后续能够调用这套环境。

---

# 3. MATLAB 第一次启动

把 MATLAB 当前文件夹切换到工程根目录。

先运行：

```matlab
setup_project;
```

然后：

```matlab
E = check_environment;
```

## 正确结果

环境检查中的必要项目都应该是：

```text
PASS
```

只要这里仍有 FAIL，就不要继续 AUTOTUNE。

然后做接口回归：

```matlab
G = run_v53_interface_regression;
assert(G.overall == "PASS");
```

这一步非常重要。

它验证的不是“当前 PID 好不好”，而是：

```text
RC输入
  ↓
ArduPilot内部目标
  ↓
控制器
  ↓
raw PWM
  ↓
执行机构映射
  ↓
舵面
  ↓
Simulink飞机响应
  ↓
Truth / 传感器
  ↓
重新送回SITL
```

如果接口 Gate 不通过，后面的 AUTOTUNE 结果没有可信度。

---

# 4. 我要换一架新无人机，第一步改哪里

不要先去 Simulink 里到处找参数。

新飞机的正式入口是：

```matlab
setup_project;
create_new_aircraft("UAV_B");
```

其中 `UAV_B` 只是示例名字，可以换成你自己的飞机 ID。

执行后，重点编辑：

```text
model/aircraft/UAV_B/aircraft_definition.m
```

新飞机的原始/外部数据放在：

```text
input/aero_data/
input/prop_data/
input/battery_data/
input/flight_data/
```

还需要建立或修改：

```text
config/aircraft/UAV_B.json
```

并在：

```text
config/project.json
```

中把：

```text
aircraft_id
```

改成你的飞机 ID。

---

# 5. 新飞机到底有哪些参数必须换

下面是最重要的一张表。

## 5.1 一级必改：飞机本体参数

| 参数族 | 典型位置/字段 | 单位 | 含义 | 为什么必须改 |
|---|---|---:|---|---|
| 飞机 ID | `aircraft_id` | - | 当前激活飞机名称 | 决定加载哪套配置 |
| 质量 | `mass` | kg | 飞机飞行质量 | 直接影响平动加速度和配平 |
| 转动惯量 | `inertia` | kg·m² | 绕机体系、相对 CG 的惯量矩阵/主惯量 | 直接决定滚转/俯仰/偏航角加速度 |
| 翼展 | `geometry.span` | m | 参考翼展 | 用于气动力/力矩归一化 |
| 机翼面积 | `geometry.area` | m² | 参考面积 | 决定气动力尺度 |
| 平均气动弦 | `geometry.chord` | m | 参考弦长 | 俯仰力矩尺度 |
| CG | `cg_xflr5` 等 | m | 重心在气动源坐标系中的位置 | 错误会直接造成力矩错误 |
| 坐标变换 | `geometry.xflr5_to_body` | - | XFLR5/气动坐标到机体系的转换 | 防止力、力矩和舵面正负号错误 |

### 惯量必须满足

惯量必须是：

- 关于当前飞机重心；
- 在本工程定义的机体系下；
- 单位为 kg·m²。

不要把 CAD 中任意基准点的惯量直接填进去。

---

## 5.2 一级必改：气动力数据

新飞机应把自己的气动数据放到：

```text
input/aero_data/
```

至少要覆盖本控制模型实际调用的：

- 基础气动力/力矩
- 速度影响
- 迎角影响
- 侧滑角影响
- 角速度导数
- 控制导数

气动数据可以来自：

- XFLR5
- OpenVSP/VSPAERO
- CFD
- 风洞
- 实飞辨识

但无论来源是什么，必须统一：

1. 坐标系；
2. 正负号；
3. 有量纲/无量纲定义；
4. 参考面积、翼展、弦长；
5. 舵偏角单位；
6. 导数是在什么 TRIM 点得到的。

不要把另一架飞机的气动导数继续留着。

---

## 5.3 一级必改：舵面机械范围

关键字段族：

```text
limits.delta_LT
limits.delta_RT
limits.delta_e
limits.delta_r
```

典型含义：

- `delta_LT`：左副翼允许偏转范围
- `delta_RT`：右副翼允许偏转范围
- `delta_e`：升降舵允许偏转范围
- `delta_r`：方向舵允许偏转范围

注意：

**“+10°”到底代表舵面上偏还是下偏，不能凭感觉填写。**

最终必须确保：

```text
ArduPilot控制意图
→ PWM变化方向
→ 舵面实际偏转方向
→ 气动力矩方向
```

四者一致。

---

# 6. PWM、舵机和舵面参数怎么换

这部分是新飞机最容易漏掉的。

## 6.1 PWM 标定

关键字段：

```text
actuator.pwm_min
actuator.pwm_trim
actuator.pwm_max
```

分别表示：

- 最小 PWM
- 中位/零舵 PWM
- 最大 PWM

不要默认所有舵机都是：

```text
1000 / 1500 / 2000
```

RC 输入端的标定和 SERVO 输出端的标定也不要混为一谈。

---

## 6.2 PWM 正方向到舵面正方向

关键字段：

```text
actuator.pwm_to_positive_surface_sign
```

它描述：

> PWM 增大时，是否产生“本工程定义的正舵偏”。

例如：

```text
+1
```

表示 PWM 增大对应正舵偏；

```text
-1
```

表示 PWM 增大对应负舵偏。

这不是“看舵机正转反转”，而是用于把电子信号方向统一到空气动力学的舵面定义。

---

## 6.3 ArduPilot SERVO_REVERSED

工程中还会涉及：

```text
servo_reversed
```

它属于飞控输出方向配置。

一定要把下面两层区分开：

```text
ArduPilot 输出是否反向
```

和：

```text
PWM → 物理舵偏的实际机械方向
```

不能为了“图上方向看起来对”同时在两处随意反号。

---

## 6.4 执行机构动态

关键字段族：

```text
actuator.time_constant
actuator.delay_s
actuator.rate_limit
actuator.deadband_pwm
```

含义分别为：

| 参数 | 含义 |
|---|---|
| `time_constant` | 舵机/舵面一阶惯性时间常数 |
| `delay_s` | 命令到实际响应的纯延迟 |
| `rate_limit` | 最大舵面变化速率 |
| `deadband_pwm` | PWM 死区 |

当前 UAV_A 工程中曾使用过的参考值包括：

```text
time_constant = 0.035 s
delay_s       = 0.004 s
rate_limit    ≈ 6.4577 rad/s
deadband_pwm  = 5
```

**这些只是当前飞机模型的值，不是新飞机默认值。**

新飞机应优先使用：

1. 实测舵机数据；
2. 台架测量；
3. 舵机规格 + 保守建模；
4. 最后才是沿用参考值。

---

# 7. RC 和 ArduPilot 参数也必须换

需要建立：

```text
config/aircraft/UAV_B.json
```

这里至少要检查：

- RC 最小值
- RC 中位值
- RC 最大值
- RC 通道映射
- SERVO 输出通道
- 舵面限位
- 反向设置
- 与当前飞机一致的 ArduPilot 参数基线

当前工程典型 RC 范围是：

```text
1000 / 1500 / 2000
```

典型输出通道涉及：

```text
1 / 2 / 3 / 4 / 5
```

但新飞机必须以真实接线、飞控参数和 RC 校准为准。

特别注意：

```text
ap.*
```

相关 ArduPilot 参数必须来自**这架飞机自己的参数文件/参数基线**。

不要把 UAV_A 的飞控参数整体复制给 UAV_B 后直接拿来实飞。

---

# 8. 新飞机配置完成后，怎么检查

编辑完：

```text
model/aircraft/UAV_B/aircraft_definition.m
```

后，先确认文件里所有占位值和 `NaN` 都已经处理。

只有真正完成后才把：

```matlab
A.config_complete = true;
```

然后依次运行：

```matlab
verify_aircraft_workspace("UAV_B");
```

通过后：

```matlab
set_active_aircraft("UAV_B");
```

然后：

```matlab
P = init_uav_model("UAV_B");
```

这三步的意义分别是：

### `verify_aircraft_workspace`
检查新飞机配置是不是缺参数、留了占位符、路径错误或明显不完整。

### `set_active_aircraft`
把工程当前飞机切换到指定 ID。

### `init_uav_model`
真正生成仿真所需的统一参数结构。

---

# 9. 一个非常重要的当前版本限制

**V5.4.1-Validation-Fix 当前仍存在 `UAV_A` / `config/project.json` 的硬编码或绑定。**

因此：

```text
create_new_aircraft("UAV_B")
```

能帮助你建立新飞机工作区，

但这**不等于当前版本已经完整证明 UAV_B 可以直接进入 Native AUTOTUNE 全流程**。

换句话说：

```text
新飞机数据能加载
≠
全部测试入口都已经彻底摆脱 UAV_A
≠
Native AUTOTUNE 已完成新飞机迁移验证
```

在真正使用新飞机跑 Native AUTOTUNE 前，至少必须重新确认：

```matlab
G = run_v53_interface_regression;
assert(G.overall == "PASS");
```

并检查所有 AUTOTUNE 顶层脚本是否仍引用 UAV_A 专属数据、路径、参数快照或结果目录。

**不能只改 `aircraft_id` 就认为迁移完成。**

---

# 10. 开始 AUTOTUNE 前为什么还要做“物理控制权检查”

运行：

```matlab
C = run_v541_physical_control_authority;
```

它回答的是：

> 这架飞机在当前执行机构、舵面范围、速度和气动模型下，到底有没有足够控制能力完成 AUTOTUNE 激励？

它不是在评价 PID。

即使 PID 还没调好，也应该先检查：

- 舵面方向正确；
- 有控制力矩；
- 不会因为限位/速率限制完全打不动；
- 仿真模型没有明显的正负号错误；
- Roll/Pitch/Yaw 的控制权数量级合理。

---

# 11. AUTOTUNE_LEVEL 怎么选

运行：

```matlab
F = generate_autotune_level_feasibility_v541;
```

这个步骤用于先筛查：

- 哪些 AUTOTUNE_LEVEL 的激励幅度可行；
- 是否会触碰姿态包线；
- 是否会大量舵面饱和；
- 当前飞机在对应 Level 下有没有足够控制权。

不要把“Level 越高”理解成“参数越好”。

Level 越高通常意味着更激进的目标带宽/激励要求，同时也更容易暴露：

- 舵面饱和；
- 速率限制；
- 延迟；
- 非线性；
- 气动模型线性区间不足。

---

# 12. 正式开始 Native AUTOTUNE

当前正式重复性入口：

```matlab
R = run_v541_autotune_repeatability( ...
    Level=2, ...
    Count=3, ...
    RollCycles=30, ...
    PitchCycles=20, ...
    ActuatorFidelity="ENGINEERING", ...
    SensorFidelity="ENGINEERING", ...
    RandomSeed=42);
```

参数含义：

| 参数 | 含义 |
|---|---|
| `Level` | ArduPilot AUTOTUNE_LEVEL |
| `Count` | 独立重复试验次数 |
| `RollCycles` | 给 Roll AUTOTUNE 预留的激励循环数 |
| `PitchCycles` | 给 Pitch AUTOTUNE 预留的激励循环数 |
| `ActuatorFidelity` | 执行机构模型精度等级 |
| `SensorFidelity` | 传感器模型精度等级 |
| `RandomSeed` | 随机扰动的固定种子，便于重复 |

每一次 trial 会自动执行大致如下流程：

```text
启动一套新的 WSL ArduPlane SITL
→ --wipe / 恢复参数快照
→ 建立通信
→ 进入指定模式
→ 启动 AUTOTUNE
→ Simulink 飞机闭环运行
→ ArduPilot 内部搜索参数
→ 导出 DataFlash
→ 回读调参后参数
→ 保存 trial 结果
→ 停止 SITL
```

运行时不要再启动另一套占用 UDP 9002 的 ArduPlane。

---

# 13. 怎么判断 AUTOTUNE 到底成功没有

不要只看“飞机没有掉”。

要看 ArduPilot 官方完成状态和结果结构。

常见关键结果包括：

```text
result.overall
failure_reason
COMPLETE_OFFICIAL_FINISHED
R.roll.status
R.pitch.status
R.status
```

每个 trial 还会保存类似：

```text
trial_result.json
result.json
internal_MSG.csv
AUTOTUNE_TIMELINE.csv
```

重复性验证除了要求完成，还要检查参数统计。

当前正式判据之一：

```text
参数族 CV <= 15%
```

也就是说，重复跑出来的参数不能飘得很厉害。

最终通常要求：

```matlab
R.status == "PASS"
```

才可认为该重复性验证通过。

---

# 14. AUTOTUNE 最终得到什么

最终会得到 ArduPlane 的控制参数，包括对应轴的：

```text
FF
P
I
D
```

但请注意 Native AUTOTUNE 不是一个“surrogateopt 找全局最优”的黑箱优化器。

它的思想更接近：

```text
估计 FF
→ 提高 D，寻找过强/振荡边界
→ 回退
→ 提高 P，寻找过强/振荡边界
→ 回退
→ 根据 P / FF 等关系形成 I
→ 满足官方完成条件
→ Finished
```

所以“找到边界”是调参过程的一部分，最终使用的是经过回退和规则处理后的可用参数。

---

# 15. 最终结果在哪里看

先看：

```text
results/v5_4_1/RESULT.md
```

然后再进入各次运行目录看：

```text
result.json
trial_result.json
AUTOTUNE_TIMELINE.csv
internal_MSG.csv
统计 CSV
DataFlash
plots/
```

建议阅读顺序：

```text
RESULT.md
→ 总体 PASS/FAIL
→ Roll/Pitch status
→ trial_result.json
→ 参数统计
→ AUTOTUNE_TIMELINE.csv
→ DataFlash / MSG
→ plots
```

不要一上来就翻几千行日志。

---

# 16. 最短工作流：当前飞机

如果你只想快速跑当前飞机：

```matlab
setup_project;

E = check_environment;

G = run_v53_interface_regression;
assert(G.overall == "PASS");

C = run_v541_physical_control_authority;

F = generate_autotune_level_feasibility_v541;

R = run_v541_autotune_repeatability( ...
    Level=2, ...
    Count=3, ...
    RollCycles=30, ...
    PitchCycles=20, ...
    ActuatorFidelity="ENGINEERING", ...
    SensorFidelity="ENGINEERING", ...
    RandomSeed=42);

generate_v541_validation_fix_report;
```

结果：

```text
results/v5_4_1/RESULT.md
```

---

# 17. 最短工作流：新飞机

假设新飞机 ID 为 `UAV_B`：

```matlab
setup_project;

create_new_aircraft("UAV_B");
```

然后修改：

```text
model/aircraft/UAV_B/aircraft_definition.m
config/aircraft/UAV_B.json
config/project.json
input/aero_data/
input/prop_data/
input/battery_data/
input/flight_data/
```

必须重新确认：

```text
质量
惯量
几何
CG
坐标系
气动数据
推进数据
舵面范围
PWM范围
舵机方向
执行机构动态
RC标定
飞控通道
飞行速度范围
ArduPilot参数基线
```

完成后：

```matlab
verify_aircraft_workspace("UAV_B");
set_active_aircraft("UAV_B");
P = init_uav_model("UAV_B");
```

然后：

```matlab
G = run_v53_interface_regression;
assert(G.overall == "PASS");
```

**到这里仍只能说明“新飞机基础模型和接口可以进入验证”。**

由于当前 V5.4.1 仍有 UAV_A 绑定，必须在确认 AUTOTUNE 全部入口已经移除 UAV_A 专属引用后，才进入正式 Native AUTOTUNE。

---

# 18. 新飞机参数检查清单

在正式仿真前逐项打勾：

```text
[ ] aircraft_id 正确
[ ] aircraft_definition.m 已完成
[ ] config_complete = true
[ ] 不存在 NaN / TODO / placeholder
[ ] 质量正确
[ ] 惯量关于 CG 且坐标系正确
[ ] span / area / chord 正确
[ ] CG 正确
[ ] XFLR5/气动坐标 → body 坐标转换正确
[ ] 气动力/力矩正负号正确
[ ] 控制导数与舵面正方向一致
[ ] 左副翼范围正确
[ ] 右副翼范围正确
[ ] 升降舵范围正确
[ ] 方向舵范围正确
[ ] PWM min/trim/max 正确
[ ] PWM 增大对应的实际舵偏方向已确认
[ ] SERVO_REVERSED 已确认
[ ] 舵机 time constant 已确认
[ ] 舵机 delay 已确认
[ ] rate limit 已确认
[ ] deadband 已确认
[ ] RC 标定正确
[ ] RC/SERVO 通道映射正确
[ ] cruise_speed 正确
[ ] stall_speed 正确
[ ] Va_min / Va_max 合理
[ ] ArduPilot 参数来自当前飞机
[ ] verify_aircraft_workspace 通过
[ ] interface regression PASS
[ ] physical control authority 通过
[ ] AUTOTUNE_LEVEL feasibility 可接受
```

---

# 19. 常见错误

## 错误 1：PID 还没调好，所以接口测试飞机跟不上指令就是 FAIL

不对。

接口测试的首要目标是确认：

```text
RC/PWM/舵面/Truth/传感器/UDP
```

信号链正确。

“未调参时姿态跟踪不好”本身不是接口故障。

---

## 错误 2：Simulink 直接给 ArduPilot 一个滚转角

正式接口不应该这样做。

工程应走类似真实系统的链：

```text
测试输入
→ RC
→ ArduPilot
→ PWM
→ 执行机构
→ 飞机
```

而不是绕过飞控内部控制器。

---

## 错误 3：改了质量和翼展就算换机完成

不对。

至少还涉及：

```text
惯量
CG
气动
推进
舵面
PWM
舵机动态
RC
飞控参数
坐标系
```

---

## 错误 4：看到 AUTOTUNE 有一组新 PID，就认为成功

不对。

至少还要确认：

- 官方 `Finished`
- trial 完整结束
- 参数成功回读
- 重复性
- Gate
- 后续闭环验证

---

## 错误 5：把当前 UAV_A 的舵机曲线直接用于新飞机

当前工程中 UAV_A 只有部分舵面映射有实测依据；右副翼、升降舵、方向舵曾存在沿用/缩放左副翼曲线的工程近似。

因此新飞机**不能直接复制这些近似后用于飞行放行**。

---

# 20. 什么时候应该看详细说明

遇到下面问题时，转到：

```text
README_详细说明.md
```

详细文档会解释：

- 为什么 Simulink 是 Truth Model
- MATLAB 与 SITL 如何通信
- UDP 9002 / 14550 / 14551 / 14552 分别干什么
- RC → target → PWM → 舵面的完整信号链
- 6DOF 模型如何组成
- 气动/推进/执行机构/传感器模块分别做什么
- Native AUTOTUNE 内部为什么先 FF 再 D/P
- Roll/Pitch 为何可能完成速度不同
- 每个顶层脚本的职责
- Gate 是怎么分层判断的
- DataFlash / JSON / CSV 分别记录什么
- 新飞机迁移为什么不能只改一个 ID
- 当前 V5.4.1 的工程边界与已知限制
