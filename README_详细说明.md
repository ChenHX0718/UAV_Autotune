# UAV Autotune 详细说明

> 适用版本：**5.4.1-Validation-Fix**  
> 文档定位：这是工程使用与技术架构说明，不是毕业论文。  
> 目标：让接手工程的人能够回答“每个模块在干什么、信号怎么走、参数从哪里来、AUTOTUNE 到底在哪里运行、结果怎么形成、为什么一个 Gate 失败就不能继续”的问题。

---

# 1. 项目定位

本工程的目标不是建立一架“所有气动非线性、结构弹性、传感器噪声、执行机构负载都完全等价于实机”的数字孪生。

更准确的定位是：

> **面向固定翼控制调参与 ArduPilot Native AUTOTUNE 验证的工程参考模型。**

它当前适合用于：

- 检查 Simulink ↔ SITL 接口
- 检查 RC/PWM/舵面信号链
- 分析控制权
- 筛选 AUTOTUNE_LEVEL
- 运行 ArduPlane Native AUTOTUNE
- 比较重复调参结果
- 发现 Roll/Pitch/Yaw 控制问题
- 在实飞前做候选参数和风险筛查

它当前不应被理解为：

- 参数一跑出来就可直接实飞
- 仿真 PASS 就等于飞行放行
- 气动模型已经覆盖所有失速/大迎角非线性
- 所有舵机动态都经过实测
- 所有新飞机只改 ID 就能无缝 AUTOTUNE

---

# 2. 当前版本状态

版本：

```text
5.4.1-Validation-Fix
```

当前正式结果：

```text
Roll Level 2 repeatability: 3/3 PASS
Pitch official Finished:    0/3 within 180 s
Overall validation:         INCOMPLETE
```

因此：

> 当前工程已经证明 Roll Level 2 的重复性链路可以走通，但尚未证明 Roll + Pitch 两轴均完成 Native AUTOTUNE 并通过完整后验证。

最终正式结果入口：

```text
results/v5_4_1/RESULT.md
```

---

# 3. 总体架构

## 3.1 三个核心系统

```text
┌────────────────────────────────────────────┐
│ MATLAB                                     │
│ 配置 / 试验编排 / WSL管理 / 日志解析 / Gate │
└─────────────────┬──────────────────────────┘
                  │
                  │ 启停、参数、UDP/JSON、结果
                  ▼
┌────────────────────────────────────────────┐
│ ArduPilot ArduPlane SITL                   │
│ 飞控模式 / RC / 控制器 / Native AUTOTUNE   │
└─────────────────┬──────────────────────────┘
                  │ PWM / servo output
                  ▼
┌────────────────────────────────────────────┐
│ Simulink Truth Model                       │
│ Actuator → Aero/Prop → 6DOF → Sensors      │
└─────────────────┬──────────────────────────┘
                  │ Truth / sensor data
                  └──────────────→ SITL
```

---

# 4. 为什么 Simulink 是唯一 Truth Model

工程设计原则是：

> 飞机的真实物理状态只由 Simulink 动力学模型产生。

ArduPilot SITL 不再使用自己内部的简化飞机模型作为最终真值，而是接收 Simulink 回传的飞机运动/传感器状态。

因此：

```text
ArduPilot 发出控制命令
→ Simulink 执行控制面/动力系统
→ 计算气动力、推力、6DOF
→ 得到飞机实际状态
→ 转换成 SITL 所需传感器/Truth 数据
→ 回传给 ArduPilot
```

这样做的意义是：

1. 飞控内部逻辑仍是真实 ArduPlane；
2. 飞机物理模型可以由用户修改；
3. 不需要在 MATLAB 里重写 ArduPilot 控制器；
4. 更接近“控制器在环 + 外部动力学模型”的软件在环结构。

---

# 5. ArduPilot SITL 负责什么

ArduPlane SITL 运行的是真实 ArduPilot 固定翼代码路径。

它负责：

```text
RC input
→ mode logic
→ FBWA / AUTOTUNE
→ attitude target
→ rate target
→ controller
→ mixer / servo function
→ PWM output
```

Native AUTOTUNE 也发生在这里。

MATLAB 不负责：

- 自己搜索 ArduPlane P/I/D
- 模拟一个假的 AUTOTUNE 状态机
- 直接写 desired roll 绕过 RC
- 直接把角度命令送到舵面

---

# 6. MATLAB 负责什么

MATLAB 是“试验总控”。

主要职责：

1. 初始化工程；
2. 读取飞机配置；
3. 检查依赖；
4. 启动/停止 WSL SITL；
5. 管理 ArduPilot 参数快照；
6. 生成试验输入；
7. 启动 Simulink；
8. 管理 UDP/JSON；
9. 读取参数；
10. 导出/解析 DataFlash；
11. 计算 Gate；
12. 保存 CSV/JSON/图/报告；
13. 组织重复性试验。

因此 MATLAB 是：

```text
experiment orchestrator
```

不是：

```text
flight controller
```

---

# 7. 已验证环境

| 项目 | 值 |
|---|---|
| Windows | Windows 10 22H2 build 19045 |
| WSL | WSL2 |
| Linux | Ubuntu 24.04 LTS / `Ubuntu-24.04` |
| MATLAB | R2024b 24.2 |
| Python | 3.12.3 |
| ArduPlane branch/tag | `Plane-4.7.0` |
| ArduPilot commit | `1511f27194f1dcc3728270883047bdf022b3fd53` |
| target | `sitl/plane` |
| binary | `build/sitl/bin/arduplane` |

固定端口：

| UDP | 用途 |
|---:|---|
| 9002 | Simulink ↔ SITL 闭环数据 |
| 14550 | Mission Planner |
| 14551 | headless MAVLink |
| 14552 | WSL 控制/辅助链路 |

端口冲突会导致：

- 数据送错进程；
- SITL 看似启动但无闭环；
- MATLAB 收不到预期包；
- 参数回读对应了错误实例。

因此同一测试期间不要启动额外占用相同端口的 ArduPlane。

---

# 8. 根目录两份说明文档的分工

工程根目录应只保留两份面向用户的说明：

```text
README_快速使用.md
README_详细说明.md
```

历史报告、实验日志、结果说明统一进入：

```text
results/
```

而不是继续在根目录堆：

```text
V5.2说明.md
V5.3修复说明.md
Pitch问题分析.md
最终最终说明_v2.md
...
```

---

# 9. 工程入口函数

## 9.1 `setup_project`

作用：

- 把工程需要的 MATLAB 路径加入 path；
- 建立统一工程根目录；
- 准备后续函数调用。

新 MATLAB 会话建议第一个运行：

```matlab
setup_project;
```

---

## 9.2 `check_environment`

调用：

```matlab
E = check_environment;
```

作用：

检查：

- MATLAB 环境；
- WSL；
- Ubuntu；
- ArduPilot；
- build；
- 关键路径；
- 运行前依赖。

原则：

> 环境 Gate 未通过，不进入控制层调试。

---

## 9.3 `run_v53_interface_regression`

调用：

```matlab
G = run_v53_interface_regression;
assert(G.overall == "PASS");
```

它是非常关键的接口 Gate。

检查重点包括：

```text
RC
→ ArduPilot internal target
→ raw PWM
→ actuator mapping
→ surface deflection
→ Simulink Truth
→ feedback
```

并检查：

- 数据包
- 时间戳
- 参数回读
- headless 流程
- 不依赖 Mission Planner GUI

它的目的不是证明 PID 已经调好。

---

## 9.4 `run_v541_physical_control_authority`

调用：

```matlab
C = run_v541_physical_control_authority;
```

作用：

在进入 AUTOTUNE 前确认飞机模型本身有足够控制能力。

重点看：

- 舵面方向；
- 舵面限位；
- 执行机构速率；
- 气动控制导数；
- 当前速度；
- 姿态响应方向；
- 是否严重饱和。

它解决的问题是：

> “这架飞机能不能被控制？”

不是：

> “当前参数是不是最优？”

---

## 9.5 `generate_autotune_level_feasibility_v541`

调用：

```matlab
F = generate_autotune_level_feasibility_v541;
```

作用：

针对候选 AUTOTUNE_LEVEL 做可行性筛查。

典型分析：

- 激励大小；
- 角速度需求；
- 舵面饱和；
- 姿态包线；
- 控制权余量；
- 执行机构动态是否跟得上。

---

## 9.6 `run_v541_autotune_repeatability`

当前正式调用示例：

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

每个 trial 的逻辑：

```text
fresh SITL
→ wipe / parameter snapshot
→ load baseline
→ communication ready
→ AUTOTUNE
→ Simulink closed loop
→ DataFlash export
→ parameter readback
→ trial result
→ stop SITL
```

这个 fresh-restart 逻辑非常重要，因为否则：

- 上一次 trial 的参数可能污染下一次；
- AUTOTUNE 状态可能残留；
- 无法真正证明重复性。

---

## 9.7 `generate_v541_validation_fix_report`

调用：

```matlab
generate_v541_validation_fix_report;
```

作用：

把环境、接口、控制权、AUTOTUNE 和重复性结果整理为正式报告。

最终入口：

```text
results/v5_4_1/RESULT.md
```

---

# 10. 新飞机配置架构

创建：

```matlab
setup_project;
create_new_aircraft("UAV_B");
```

新飞机核心定义：

```text
model/aircraft/UAV_B/aircraft_definition.m
```

外部数据：

```text
input/aero_data/
input/prop_data/
input/battery_data/
input/flight_data/
```

工程选择：

```text
config/project.json
```

飞机级飞控/接口配置：

```text
config/aircraft/UAV_B.json
```

验证和激活：

```matlab
verify_aircraft_workspace("UAV_B");
set_active_aircraft("UAV_B");
P = init_uav_model("UAV_B");
```

---

# 11. `aircraft_definition.m` 应该表达什么

它应该成为：

> “一架飞机的唯一高层物理定义入口。”

它不应该要求用户去十几个脚本中分别修改相同质量、翼展、惯量。

至少需要统一描述以下参数族。

---

# 12. 质量与惯量模块

## 12.1 `mass`

单位：

```text
kg
```

表示飞行状态下的总质量。

必须明确使用哪种状态：

- 空机
- 含电池
- 含载荷
- 起飞质量
- 某一试验质量

控制仿真一般应使用与目标调参工况一致的质量。

---

## 12.2 `inertia`

单位：

```text
kg·m²
```

惯量必须满足两个条件：

```text
about CG
body frame
```

也就是：

- 参考点是重心；
- 坐标轴与本工程机体系一致。

若 CAD 给出的惯量关于另一坐标系或另一原点，必须换算。

惯量错误最直接的后果：

- Roll/Pitch/Yaw 角加速度数量级错误；
- AUTOTUNE 边界错误；
- 得到的参数在实机上偏激进或偏保守。

---

# 13. 几何模块

核心量：

```text
geometry.span
geometry.area
geometry.chord
```

单位：

```text
span  : m
area  : m²
chord : m
```

用途：

```text
q*S
q*S*b
q*S*c
```

分别用于：

- 力；
- 滚转/偏航力矩；
- 俯仰力矩。

因此参考量必须和气动数据源使用的定义一致。

---

# 14. 重心和坐标系

典型字段：

```text
cg_xflr5
geometry.xflr5_to_body
```

这是全工程最危险的一类参数。

如果 XFLR5/OpenVSP 坐标系和 Simulink body frame 不一致，需要完整处理：

```text
位置
速度
力
力矩
舵偏角
角速度
```

的方向约定。

不能只把 `X` 改成 `-X` 就认为全部处理完成。

详细检查至少包括：

```text
+X_body
+Y_body
+Z_body
positive roll
positive pitch
positive yaw
positive elevator
positive rudder
positive left/right aileron
```

最终检查原则是：

> 一个正控制指令必须通过整条链产生正确符号的气动力矩。

---

# 15. 气动模块

气动模块的输入通常来自：

```text
input/aero_data/
```

其任务是根据：

- 空速
- 迎角 α
- 侧滑角 β
- 角速度 p/q/r
- 舵面偏角
- 当前参考状态

计算：

```text
Force_body
Moment_body
```

或等价的气动系数。

---

# 16. 气动导数的工程意义

控制模型常用：

```text
Cl_p
Cl_delta_a
Cm_q
Cm_delta_e
Cn_r
Cn_delta_r
...
```

这些量必须明确：

1. 导数定义；
2. 无量纲方式；
3. 角度单位是 rad 还是 deg；
4. 参考动压；
5. TRIM 点；
6. 坐标系；
7. 正负号。

例如同一个“升降舵控制导数”，如果一个数据源用：

```text
TE down positive
```

另一个模型用：

```text
TE up positive
```

符号会完全相反。

---

# 17. 线性导数模型的边界

当前控制模型中大量气动导数本质上是局部线性化量。

它们最可靠的区域是：

> 导数计算 TRIM 点附近。

Native AUTOTUNE 会主动提高 P/D，寻找接近过强响应或振荡的边界，因此运动幅度可能比普通小扰动更大。

这意味着：

- 线性模型仍可用于工程趋势和 AUTOTUNE 筛查；
- 但当迎角、侧滑、舵偏明显离开线性区域时，模型误差会放大；
- 如果要提高最终参数可信度，应使用多工况、插值或更完整非线性气动模型，而不是无限相信单一 TRIM 点导数。

---

# 18. 推进模块

推进数据放在：

```text
input/prop_data/
```

推进模块至少要能根据当前工况描述：

```text
throttle / command
→ motor / propeller operating point
→ thrust
→ optional torque
```

传统简化字段可能包括：

```text
prop.max_static_thrust
```

单位：

```text
N
```

但如果有实测桨/电机数据，优先使用随空速、转速或功率变化的推进模型。

原因是固定翼中：

```text
静拉力
≠
巡航拉力
```

尤其电涵道和高前进比螺旋桨差异会更明显。

---

# 19. 执行机构模块

执行机构位于：

```text
PWM
→ physical surface
```

之间。

它至少解决四个问题：

1. 信号方向；
2. 非线性映射；
3. 延迟；
4. 速度/幅度限制。

---

# 20. PWM 映射

关键参数：

```text
actuator.pwm_min
actuator.pwm_trim
actuator.pwm_max
actuator.pwm_to_positive_surface_sign
```

逻辑：

```text
raw PWM
→ subtract trim
→ normalize
→ apply direction
→ map to physical angle
```

如果存在实测“PWM—舵偏角曲线”，应优先使用实测曲线，而不是简单线性映射。

---

# 21. 当前舵面映射的已知近似

当前 UAV_A 中并不是所有舵面映射都同等可信。

已知工程状态：

> 左副翼曲线有较直接的实测依据，而右副翼、升降舵、方向舵曾存在沿用或缩放左副翼曲线的工程近似。

因此这些近似：

- 可以用于工程级仿真；
- 不能作为新飞机通用舵机模型；
- 更不能直接视为实飞标定。

---

# 22. 执行机构动态

关键字段：

```text
actuator.time_constant
actuator.delay_s
actuator.rate_limit
actuator.deadband_pwm
```

数学上可理解为：

```text
command
→ pure delay
→ first-order lag
→ rate saturation
→ position saturation
→ deadband/nonlinearity
```

其中：

### `time_constant`
模拟舵机及舵面的有限响应速度。

### `delay_s`
模拟电控、通讯、内部处理和机械响应前的等效延迟。

### `rate_limit`
模拟最大偏转速度。

### `deadband_pwm`
模拟 PWM 小变化无法驱动舵面的死区。

当前工程曾使用的参考量：

```text
0.035 s
0.004 s
≈ 6.4577 rad/s
5 PWM
```

它们不是所有飞机的标准值。

---

# 23. 为什么舵机不能只建一个“最大角度”

AUTOTUNE 特别依赖动态过程。

如果仿真里舵机：

```text
PWM一变
→ 舵面瞬间到位
```

会低估：

- 相位滞后；
- 速率饱和；
- 执行机构极限；
- 高频控制损失。

最终容易把 AUTOTUNE 参数调得过激进。

---

# 24. 传感器模块

传感器模块的作用不是“给图加一点噪声”。

它位于：

```text
Simulink Truth
→ ArduPilot observed state
```

之间。

可包含：

- 噪声；
- 偏置；
- 延迟；
- 采样；
- 滤波；
- 量化；
- 数据丢失/抖动。

当前重复性入口提供：

```matlab
SensorFidelity="ENGINEERING"
```

说明传感器模型可按不同 fidelity 运行。

---

# 25. 环境模块

典型环境参数包括：

```text
g
wind_ned
```

其中：

```text
g : m/s²
wind_ned : [north east down] m/s
```

环境模块应向 Truth Model 提供：

- 重力；
- 风；
- 需要时的空气密度/大气条件。

---

# 26. 6DOF 模块

6DOF 的核心任务是：

```text
ΣForce
ΣMoment
mass
inertia
→ translational acceleration
→ angular acceleration
→ velocity / attitude / position
```

它是整个物理链的积分核心。

输入错误不会只影响一个模块。

例如：

```text
Cm_delta_e 符号错
```

会表现成：

```text
升降舵响应方向错
→ Pitch控制器越控越偏
→ AUTOTUNE不完成
→ 甚至被误判成PID问题
```

所以先做物理控制权 Gate，而不是直接调 PID。

---

# 27. RC → PWM → 舵面的完整链

这一条必须彻底理解：

```text
test excitation
    ↓
RC command
    ↓
ArduPilot RC calibration
    ↓
mode / target generation
    ↓
attitude controller
    ↓
rate controller
    ↓
servo function / mixer
    ↓
SERVOx output
    ↓
raw PWM
    ↓
Simulink actuator model
    ↓
surface deflection
    ↓
aerodynamic moment
    ↓
6DOF
```

因此：

> Simulink 不应该直接收到一个“滚转角命令后自己控制到该角度”。

那样会绕过飞控内部真实逻辑。

---

# 28. 为什么使用 RC/PWM 而不是直接传角度

如果 MATLAB 直接给动力学模型：

```text
roll_target = 10 deg
```

并在 MATLAB 里自己算舵面，

那 ArduPilot 的：

- RC calibration
- mode logic
- controller
- output scaling
- reversal
- SERVO function
- Native AUTOTUNE

就被部分绕过。

这样的模型即使“姿态跟得很好”，也不能证明真实飞控链路正确。

---

# 29. JSON/FDM 与 UDP 通信

工程通过 Windows/WSL 之间的 UDP/JSON-FDM 进行闭环。

核心逻辑：

```text
SITL control output
→ UDP
→ MATLAB/Simulink
→ plant update
→ Truth/sensors
→ JSON/FDM/UDP
→ SITL
```

正式测试必须关注：

- 数据格式；
- 单位；
- 时间戳；
- 包间隔；
- 丢包；
- jitter；
- 端口；
- 进程实例。

---

# 30. 时间同步为什么重要

如果 Simulink 和 SITL 的时间基准漂移，会出现：

- 控制命令对错状态；
- 传感器滞后被放大；
- 记录的 phase 不可信；
- AUTOTUNE 对动态的判断偏移。

建议每次试验保存：

```text
Simulink time
SITL time
wall-clock
packet timestamp
```

并统计：

```text
jitter mean
jitter P95
jitter max
packet interval
packet loss
```

---

# 31. 为什么需要 headless 流程

Mission Planner 可以用于观察，但不应该成为自动试验的必要条件。

因此工程保留：

```text
14550 Mission Planner
14551 headless MAVLink
14552 control/helper
```

正式回归应能在不依赖 GUI 操作的情况下：

- 启动；
- 切模式；
- 读写参数；
- 导出结果；
- 停止。

否则重复性试验无法自动化。

---

# 32. Native AUTOTUNE 的控制逻辑

ArduPlane Native AUTOTUNE 不是一个“给参数范围然后全局搜索最低 cost”的优化器。

可概括为：

```text
FF identification
→ raise D
→ detect excessive/oscillatory boundary
→ back off
→ raise P
→ detect excessive/oscillatory boundary
→ back off
→ form I
→ repeat valid cycles
→ Finished
```

其关键特点是：

> 它主动寻找控制边界，再退回可用参数。

---

# 33. FF 的意义

FF 是前馈。

固定翼舵面控制中，它用于：

> 根据目标角速度/控制需求，提前给出一部分理论上需要的舵面量。

良好的 FF 可以：

- 降低 P 的负担；
- 改善动态；
- 让反馈项主要处理误差和模型不确定性。

---

# 34. 为什么 AUTOTUNE 要提高 D/P

AUTOTUNE 需要知道：

> 当前飞机 + 当前速度 + 当前执行机构 + 当前传感器链，到底能承受多大的闭环增益。

所以会逐步提高增益，观察：

- 过冲；
- 速率；
- 振荡；
- 反转；
- slew；
- 内部判据。

找到边界后退回，而不是把边界值直接当最终值。

---

# 35. I 为什么不是单独暴力搜索

Native AUTOTUNE 中 I 更多根据：

- P；
- FF；
- 飞控内部规则

形成，而不是像 P/D 那样独立反复探边界。

所以不要把它想象成：

```text
FF×100种
P×100种
I×100种
D×100种
```

的穷举。

---

# 36. 官方 `Finished` 为什么重要

不能用：

```text
“曲线看起来差不多”
```

替代：

```text
Pitch: Finished
Roll: Finished
```

因为 AUTOTUNE 内部可能仍处在：

```text
RAISE_D
RAISE_PD
LOWER_D
LOWER_P
```

等阶段。

如果还没有 Finished，参数可能只是中间状态。

---

# 37. 180 s 是什么

当前 Pitch 的约 180 s 限制来自工程试验脚本预留的循环/运行窗口，不应误解为：

> ArduPilot 自己规定 180 s 必须结束。

当前证据中 Pitch 在时间耗尽时仍可能处于增益推进阶段，因此：

```text
180 s 内未 Finished
```

只能说明：

```text
本次工程试验窗口内未完成
```

不能自动证明：

```text
Pitch永远无法AUTOTUNE
```

---

# 38. AUTOTUNE_LEVEL 的意义

Level 不是简单的“好/坏等级”。

它会影响：

- 目标带宽；
- 目标时间常数；
- 允许/期望的动态；
- 激励要求。

高 Level 更容易要求：

- 更快舵机；
- 更高控制权；
- 更小延迟；
- 更强气动响应。

所以必须先运行：

```matlab
generate_autotune_level_feasibility_v541
```

而不是盲目拉高 Level。

---

# 39. 为什么先做 Physical Control Authority

假设升降舵控制导数错了 50%，或者舵机偏转范围只建了一半。

直接跑 AUTOTUNE 后可能得到：

- 异常大 P；
- 异常小 D；
- 长时间不 Finished；
- 大量 saturation。

这些表面上像“调参算法问题”，实际是：

```text
plant model / control authority
```

有问题。

所以顺序必须是：

```text
interface
→ physical authority
→ level feasibility
→ autotune
```

---

# 40. Gate 分层逻辑

工程不应该只有一个：

```text
PASS / FAIL
```

而应该逐层回答不同问题。

## Gate 0：Environment

问：

> 软件环境能不能跑？

---

## Gate 1：Interface

问：

> 信号链是真的按设计在传吗？

检查：

```text
RC
target
PWM
surface
Truth
sensor
timestamps
packet
parameter readback
```

---

## Gate 2：Physical Control Authority

问：

> 飞机模型在物理上有没有可调性？

---

## Gate 3：AUTOTUNE Official Completion

问：

> ArduPilot 自己是否明确报告 Finished？

---

## Gate 4：Repeatability

问：

> fresh restart 后多次调参是否得到相近结果？

当前关键统计之一：

```text
CV <= 15%
```

---

## Gate 5：Post-tune Validation

问：

> 得到的参数在独立闭环验证中表现是否真的可接受？

这一步不应和 AUTOTUNE 本身使用完全相同的唯一激励。

---

# 41. 为什么 AUTOTUNE 后还要独立验证

即使三次 AUTOTUNE 得到完全相同参数，也只证明：

> AUTOTUNE 算法对当前模型有重复性。

它不自动证明：

> 这些参数对应的飞行品质好。

所以要有独立验证：

- step；
- doublet；
- 多速度；
- 轨迹跟踪；
- 约束检查；
- 饱和检查。

未来还可以增加用户提出的：

```text
8字轨迹
理想轨迹 vs 实际轨迹
```

作为更直观的最终接受测试。

---

# 42. 为什么“自动调参能控，验证却可能不好”

因为两者目标不同。

AUTOTUNE 激励主要服务于：

```text
identify gain boundary
```

后验证关注：

```text
tracking
overshoot
settling
saturation
robustness
trajectory quality
```

一个参数集可以：

```text
成功完成AUTOTUNE
```

但在：

```text
轨迹跟踪 / 速度变化 / 外扰
```

下表现一般。

这并不矛盾。

---

# 43. 重复性试验

正式重复性入口：

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

设计目的：

```text
same aircraft
same baseline
same environment
fresh process
multiple trials
```

用于判断：

- 是否稳定完成；
- 参数散布；
- trial contamination；
- 随机性影响。

---

# 44. `RandomSeed`

使用固定：

```matlab
RandomSeed=42
```

不是因为 42 本身特殊。

而是为了：

> 在比较代码修改前后时，把随机扰动固定住。

如果种子每次都变：

```text
结果变化
```

可能来自：

- 代码变化；
- 噪声变化；
- 两者共同变化。

很难定位。

---

# 45. Actuator/Sensor Fidelity

入口提供：

```text
ActuatorFidelity="ENGINEERING"
SensorFidelity="ENGINEERING"
```

这说明工程允许把模型精度分层。

合理用法是：

```text
FAST / IDEAL
→ 流程检查

ENGINEERING
→ 正式工程判断

HIGH FIDELITY
→ 有更多实测数据后
```

正式结果必须记录使用了哪一种 fidelity，避免“不同模型精度的参数被混在一起比较”。

---

# 46. 每个 trial 应保存什么

建议/现有工程结果体系至少包含：

```text
config snapshot
ArduPilot commit
ArduPilot parameter snapshot
aircraft configuration
scenario
MATLAB / WSL version
random seed
desired
RC
internal target
PWM
surface
Truth
sensor
state
timestamps
DataFlash
```

---

# 47. 结果文件

当前流程中出现的关键输出包括：

```text
result.json
trial_result.json
internal_MSG.csv
AUTOTUNE_TIMELINE.csv
summary.csv
metrics.csv
plots/
run_report.md
DataFlash
```

以及：

```text
results/v5_4_1/RESULT.md
```

---

# 48. `AUTOTUNE_TIMELINE.csv`

它用于把 AUTOTUNE 内部事件变成易读时间线。

比起直接翻完整 DataFlash，更适合快速判断：

```text
什么时候开始
什么时候 Raise D
什么时候 Raise P
有没有 Lower
什么时候 Finished
什么时候超时
```

---

# 49. `internal_MSG.csv`

用于整理 ArduPilot 内部 MSG 等关键文本事件。

特别适合定位：

- mode transition；
- AUTOTUNE 状态；
- Finished；
- error；
- timeout 原因。

---

# 50. `result.json` / `trial_result.json`

用途：

> 给脚本和人提供结构化最终状态。

应该优先看：

```text
overall
failure_reason
roll.status
pitch.status
official_finished
parameter_readback
```

而不是先从长日志猜结果。

---

# 51. 重复性统计

重复性不仅看：

```text
3/3有没有结束
```

还要看：

```text
FF
P
I
D
```

的离散程度。

当前正式规则之一：

```text
parameter-family CV <= 15%
```

CV 即：

```text
standard deviation / mean
```

它可以用来识别：

- 参数搜索不稳定；
- 初始条件敏感；
- 随机扰动敏感；
- 模型/接口存在不确定性。

---

# 52. 新飞机数据输入

新飞机原始数据建议按来源分开：

```text
input/aero_data/
input/prop_data/
input/battery_data/
input/flight_data/
```

这样做的目的：

> 原始数据和模型代码分离。

不要把 200 行 XFLR5 数据直接硬编码到控制脚本里。

---

# 53. 新飞机必须更换的参数总表

## A. Identification

```text
aircraft_id
aircraft name/version
configuration status
```

## B. Mass properties

```text
mass
CG
Ixx
Iyy
Izz
Ixy
Ixz
Iyz
```

若模型只使用对角惯量，也必须确认交叉惯量是否可以忽略。

## C. Geometry

```text
span
area
chord
reference point
coordinate transform
```

## D. Aerodynamics

```text
baseline coefficients
alpha/beta dependence
p/q/r derivatives
control derivatives
valid speed/alpha/beta range
trim point
```

## E. Propulsion

```text
thrust map
throttle map
speed dependence
motor/prop data
```

## F. Control surfaces

```text
left aileron range
right aileron range
elevator range
rudder range
sign conventions
```

## G. Actuators

```text
pwm_min
pwm_trim
pwm_max
pwm_to_positive_surface_sign
servo_reversed
time_constant
delay
rate_limit
deadband
nonlinear pwm-angle map
```

## H. RC / Autopilot

```text
RC min/trim/max
channel mapping
SERVO functions
SERVO min/trim/max
reversal
baseline AP parameters
```

## I. Operating envelope

```text
cruise_speed
stall_speed
Va_min
Va_max
```

## J. Sensor/environment

```text
sensor fidelity
wind
gravity
sample/delay/noise assumptions
```

---

# 54. `config_complete`

新飞机模板中保留：

```matlab
A.config_complete = false;
```

是一个安全机制。

只有：

- 所有必须参数已填写；
- NaN 已处理；
- 占位符已删除；
- 数据文件存在；
- 坐标系已确认；

才能改为：

```matlab
A.config_complete = true;
```

它不应该被当成“为了让检查通过先改 true”。

---

# 55. `verify_aircraft_workspace`

调用：

```matlab
verify_aircraft_workspace("UAV_B");
```

它是新飞机迁移的第一层 Gate。

理想上应检查：

- 文件存在；
- 配置完整；
- 数值有限；
- 单位合理；
- 关键数组尺寸正确；
- 数据路径正确；
- 没有 NaN；
- 没有 placeholder。

---

# 56. `set_active_aircraft`

调用：

```matlab
set_active_aircraft("UAV_B");
```

作用：

> 把项目的当前飞机切换到指定配置。

不要通过到处手改：

```matlab
UAV_A
```

字符串来切换飞机。

---

# 57. `init_uav_model`

调用：

```matlab
P = init_uav_model("UAV_B");
```

作用：

把：

```text
aircraft_definition
config JSON
input data
project config
```

汇总为仿真实际使用的统一参数结构。

任何“真正被 Simulink 使用的参数”最终都应该能追溯到这条初始化链。

---

# 58. 当前新飞机迁移的限制

V5.4.1 当前仍有：

```text
UAV_A
config/project.json
```

相关硬编码/绑定没有被完整证明已经泛化。

因此：

```text
create_new_aircraft
verify
set_active
init
```

通过，

并不能自动证明：

```text
所有 Native AUTOTUNE 顶层入口
```

都已经完全使用 UAV_B。

正式支持新飞机 Native AUTOTUNE 前应审计：

- 顶层脚本是否固定 UAV_A；
- parameter snapshot 是否是 UAV_A；
- result folder 是否写死；
- actuator curve 是否写死；
- flight condition 是否写死；
- AP 参数是否写死；
- validation baseline 是否写死。

---

# 59. 当前 `uav_config.m` 的角色

工程历史上存在：

```text
uav_config.m
```

作为显式 UAV 调参模型的中心配置文件。

其中可包含：

```text
P.paths.root
P.meta.aircraft_id
P.mass
P.inertia
P.geometry.*
P.prop.*
P.g
P.env.wind_ned
Mission Planner paths
```

随着新飞机工作区机制引入，设计目标应该是：

> `aircraft_definition.m` 成为飞机级数据源，`uav_config.m` 不再成为必须手工复制修改的第二套飞机数据库。

如果同一个质量在两个文件里各写一次，最终一定会出现配置漂移。

---

# 60. 为什么要避免重复配置源

错误设计：

```text
uav_config.m        mass = 2.1
aircraft_definition mass = 2.3
Simulink mask       mass = 2.2
```

此时没人知道到底哪个被使用。

正确目标：

```text
one source of truth
→ init
→ P
→ Simulink
```

---

# 61. Physical Control Authority 应该看什么

典型关注：

```text
roll sign
pitch sign
yaw sign
max angular acceleration
surface saturation
rate saturation
authority margin
```

尤其要检查：

```text
positive roll command
```

是否真的导致：

```text
positive roll acceleration
```

同理 Pitch/Yaw。

---

# 62. 为什么低 Level 通过、高 Level 可能失败

Level 增加后，激励并不是简单等比例“更大”。

它可能提高：

- 目标速率；
- 带宽；
- 反转频率；
- 舵机要求。

所以低 Level 的执行机构模型可以跟得上，并不意味着高 Level 也跟得上。

---

# 63. 速度工况为什么重要

固定翼控制权强烈依赖动压：

```text
q = 0.5 * rho * V^2
```

速度从：

```text
10 m/s → 20 m/s
```

动压约增加 4 倍。

因此同一组舵面偏角在不同速度下的力矩能力完全不同。

如果模型只在一个速度点验证，不能自动推广到全包线。

---

# 64. Pitch 为什么通常更容易暴露问题

Pitch AUTOTUNE 对以下因素很敏感：

- 升降舵控制导数；
- Cm_q；
- CG；
- Iyy；
- 速度；
- 升降舵范围；
- 舵机限速；
- 配平；
- 推力线；
- 传感器/滤波延迟。

所以 Pitch 不完成时，不应只修改 P/D 猜问题。

应按：

```text
interface
→ sign
→ control authority
→ actuator
→ aero
→ trim
→ timing
→ autotune state
```

顺序排查。

---

# 65. AUTOTUNE 和非线性气动

AUTOTUNE 会主动接近增益边界。

如果气动模型使用单一线性 TRIM 导数：

```text
small-disturbance model
```

在大激励下误差会增加。

提高模型可信度的路线是：

```text
single trim derivative
→ multi-speed derivative
→ multi-alpha / beta
→ trim-centered interpolation
→ nonlinear lookup / CFD / flight-ID correction
```

而不是认为：

```text
线性导数只要更精确一点就覆盖全部非线性
```

---

# 66. 结果报告应该回答什么

正式结果报告至少应直接回答：

1. 环境是否 PASS；
2. Interface Gate 是否 PASS；
3. 当前飞机配置；
4. fidelity；
5. AUTOTUNE_LEVEL；
6. Roll 是否 Finished；
7. Pitch 是否 Finished；
8. 每轴最终 FF/P/I/D；
9. 重复性；
10. 参数 CV；
11. 饱和/异常；
12. 失败原因；
13. 是否进入后验证；
14. 是否可以推荐参数；
15. 已知限制。

---

# 67. 不应该把“参数输出”当成最终输出

单独输出：

```text
P = ...
I = ...
D = ...
```

并不直观。

更合理的最终输出应同时包含：

```text
parameters
+ response plots
+ trajectory plots
+ constraints
+ PASS/WARN/FAIL
```

未来推荐加入一个：

```text
FINAL_ACCEPTANCE.png
```

包含：

```text
XY ideal vs actual
cross-track error
roll / pitch
airspeed / altitude
PWM / servo
```

这样可以直接看出“这组 AUTOTUNE 参数控制出来是什么样”。

---

# 68. 结果阅读顺序

推荐：

```text
1. RESULT.md
2. result.json
3. trial_result.json
4. repeatability statistics
5. AUTOTUNE_TIMELINE.csv
6. internal_MSG.csv
7. plots/
8. DataFlash
```

---

# 69. 为什么不要先看 DataFlash 全量日志

DataFlash 信息多，但不适合做第一层结论。

第一层应该先回答：

```text
PASS?
Finished?
failure_reason?
parameter readback?
repeatable?
```

之后才回到 DataFlash 做根因分析。

---

# 70. 调试优先级

遇到 AUTOTUNE 失败时，按以下顺序：

```text
P0 环境
P0 接口
P0 符号
P0 舵面范围
P0 控制权
P1 执行机构动态
P1 速度/配平
P1 气动模型
P1 时间同步
P2 AUTOTUNE窗口
P2 Level
P2 参数初值
```

不要第一反应就是：

```text
把PID手动改大一点再试
```

---

# 71. 常见故障：UDP 9002 被占用

表现：

- SITL 启动异常；
- Simulink 无数据；
- 收到另一实例数据；
- trial 互相污染。

处理：

> 正式 trial 前确保没有额外 ArduPlane 实例占用闭环端口。

---

# 72. 常见故障：Interface PASS 但姿态响应不好

这并不矛盾。

Interface PASS 表示：

```text
信号走对了
```

不表示：

```text
控制器已经调好
```

未调参基线本来就可能：

- 超调大；
- 慢；
- 振荡；
- 跟踪差。

---

# 73. 常见故障：舵面方向看起来对，控制仍发散

需要同时检查：

```text
RC sign
ArduPilot target sign
SERVO reverse
PWM sign
surface sign
aero derivative sign
body moment sign
```

任何一层反号，都可能被另一层反号暂时“抵消”，造成某个静态测试看起来正确、动态控制却错误。

---

# 74. 常见故障：Pitch 长时间没有 Finished

不要直接判定“模型不行”。

先看：

```text
AUTOTUNE_TIMELINE.csv
internal_MSG.csv
```

确认是在：

- Raise D；
- Raise P；
- Lower；
- waiting valid cycle；
- mode gate；
- saturation；

哪一步停住。

当前 V5.4.1 的 Pitch 结论是：

> 在工程给定窗口内没有完成，而不是已经证明其永远无法完成。

---

# 75. 常见故障：三次得到一样参数，但后验证差

这只能说明：

```text
repeatability good
```

不能说明：

```text
flight quality good
```

需要看独立后验证。

---

# 76. 常见故障：新飞机 `verify` 通过但 AUTOTUNE 异常

首先检查当前版本的：

```text
UAV_A hard-coded binding
```

因为“飞机定义加载成功”不等于“所有 V5.4.1 测试脚本都已经完全泛化”。

---

# 77. 正式使用顺序

完整推荐顺序：

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

---

# 78. 为什么顺序不能乱

错误：

```text
AUTOTUNE
→ 发现Pitch不行
→ 才查舵面方向
```

正确：

```text
environment
→ interface
→ physical model
→ level feasibility
→ autotune
→ repeatability
→ post-validation
```

越早的 Gate 失败，越不应该继续解释后面的结果。

---

# 79. 新电脑部署脚本

PowerShell：

```powershell
wsl --install -d Ubuntu-24.04
```

项目根目录：

```powershell
.\tools\setup_wsl_ardupilot.ps1 -Distro Ubuntu-24.04
.\tools\build_ardupilot_wsl.ps1 -Distro Ubuntu-24.04
.\tools\report_wsl_environment.ps1 -Distro Ubuntu-24.04
```

这些脚本的目标分别是：

```text
setup : 建立/准备 WSL ArduPilot 环境
build : 编译 ArduPlane SITL
report: 输出当前 WSL/ArduPilot 环境状态
```

---

# 80. 新飞机完整迁移流程

```matlab
setup_project;

create_new_aircraft("UAV_B");
```

填写：

```text
model/aircraft/UAV_B/aircraft_definition.m
```

准备：

```text
input/aero_data/
input/prop_data/
input/battery_data/
input/flight_data/
```

建立：

```text
config/aircraft/UAV_B.json
```

修改：

```text
config/project.json → aircraft_id
```

完成后：

```matlab
verify_aircraft_workspace("UAV_B");
set_active_aircraft("UAV_B");
P = init_uav_model("UAV_B");
```

再重新跑：

```matlab
E = check_environment;
G = run_v53_interface_regression;
C = run_v541_physical_control_authority;
F = generate_autotune_level_feasibility_v541;
```

只有以上都合理，才进入 AUTOTUNE。

---

# 81. 新飞机迁移时应优先实测的数据

优先级建议：

## P0
- 质量
- CG
- 惯量
- 舵面实际范围
- PWM 中位/上下限
- 舵面方向
- RC/SERVO 通道

## P1
- PWM—舵偏曲线
- 舵机最大速度
- 舵机延迟
- 巡航速度
- 失速速度
- 推进静态/动态数据

## P1
- 气动控制导数
- 阻尼导数
- 多速度工况

## P2
- 传感器噪声
- 高保真推进
- 大迎角非线性
- 风扰模型

---

# 82. 新飞机最容易填错的单位

特别检查：

```text
deg vs rad
g vs kg
mm vs m
N·mm vs N·m
kg·mm² vs kg·m²
rpm vs rad/s
PWM µs vs normalized [-1,1]
```

单位错误往往比 PID 初值错误严重得多。

---

# 83. 版本结果与代码结果分离

正式结果放：

```text
results/v5_4_1/
```

代码不应该因为某一次试验失败就复制成：

```text
script_fix_final2.m
script_fix_final3.m
```

结果应通过：

```text
run folder
config snapshot
commit
report
```

保存，而不是复制核心代码留历史。

---

# 84. 配置快照的重要性

每次 trial 必须能回答：

> 这次结果到底是用哪架飞机、哪套 AP 参数、哪个 commit、哪种 fidelity、哪个随机种子跑出来的？

否则一个月后看到：

```text
P=0.12 D=0.006
```

完全无法判断还能不能复现。

---

# 85. 参数回读的重要性

不能只相信“脚本认为自己写了参数”。

正式结果应从 SITL 重新读取：

```text
FF/P/I/D
```

并保存最终值。

原因：

- AUTOTUNE 可能没有提交；
- mode 退出时可能发生恢复；
- 参数可能被 clamp；
- 写入可能失败；
- 读到的才是飞控实际使用值。

---

# 86. 为什么每个 trial 要 fresh SITL

若不重启：

```text
trial 2
```

可能继承：

- trial 1 的 PID；
- estimator 状态；
- AUTOTUNE 内部状态；
- RC/mode 状态；
- 参数缓存。

那就不是独立重复试验。

---

# 87. DataFlash 的角色

DataFlash 是最终根因分析证据。

它可用于核对：

- mode；
- 参数；
- AUTOTUNE event；
- attitude；
- rate；
- servo；
- RC；
- messages。

但报告层应先把这些信息摘要出来，避免要求用户手工读 log 才知道 PASS/FAIL。

---

# 88. 当前模型精度边界

当前工程中仍需谨慎对待：

- 单一/局部线性气动导数；
- 大迎角/大侧滑；
- 执行机构在真实气动载荷下的变化；
- 未完全实测的舵机曲线；
- 传感器误差模型；
- 结构弹性；
- 推进动态；
- 未完成的新飞机泛化；
- Pitch 未完成的正式验证。

---

# 89. 当前模型可以可信回答的问题

更适合回答：

```text
接口是不是对的？
哪个Level更激进？
哪一轴控制权不足？
AUTOTUNE有没有完成？
调出来的参数是否重复？
哪个模块导致Pitch卡住？
某组参数是否明显过激？
```

---

# 90. 当前模型不应单独回答的问题

不应仅靠当前模型给出：

```text
“这组PID一定能实飞”
“失速边界一定准确”
“全部速度范围都稳定”
“新飞机只需改aircraft_id”
“Pitch没完成说明ArduPilot算法不适用”
```

---

# 91. 建议的最终接受测试

在 Native AUTOTUNE 完成后，建议把最终接受测试固定成：

```text
independent restart
→ load tuned params
→ trajectory / maneuver validation
→ constraints
→ report
```

可包含：

```text
Roll/Pitch step
doublet
multi-speed
8-shaped trajectory
wind perturbation
```

---

# 92. 推荐的最终图

一张最终汇总图可包含：

```text
1. XY ideal path vs actual path
2. cross-track error
3. roll command vs actual
4. pitch command vs actual
5. airspeed
6. altitude
7. PWM / surface deflection
8. saturation markers
```

这样用户可以从图上直接判断：

> AUTOTUNE 得到的参数到底“飞起来像什么”。

---

# 93. 维护原则

以后修改工程时，保持以下原则：

1. 飞机物理参数只保留一个权威入口；
2. 不把历史版本说明堆到根目录；
3. 结果进入 `results/`；
4. 每次正式试验记录 commit 和配置快照；
5. 先修 Gate，再调参数；
6. 不用姿态好坏替代接口正确性；
7. 不绕过 ArduPilot 内部控制逻辑；
8. 不把工程参考模型结论包装成实飞保证。

---

# 94. 最后一张总流程图

```text
                    ┌────────────────┐
                    │ setup_project  │
                    └───────┬────────┘
                            ▼
                 ┌─────────────────────┐
                 │ check_environment   │
                 └─────────┬───────────┘
                           │ PASS
                           ▼
              ┌──────────────────────────┐
              │ interface regression     │
              │ RC→PWM→surface→Truth     │
              └───────────┬──────────────┘
                          │ PASS
                          ▼
             ┌────────────────────────────┐
             │ physical control authority │
             └────────────┬───────────────┘
                          │ PASS
                          ▼
            ┌──────────────────────────────┐
            │ AUTOTUNE_LEVEL feasibility   │
            └─────────────┬────────────────┘
                          │ feasible
                          ▼
           ┌────────────────────────────────┐
           │ ArduPlane Native AUTOTUNE       │
           │ FF → D boundary → P boundary    │
           └──────────────┬─────────────────┘
                          │ Finished
                          ▼
          ┌──────────────────────────────────┐
          │ fresh-restart repeatability      │
          │ Count=3 / CV / parameter readback│
          └───────────────┬──────────────────┘
                          │ PASS
                          ▼
       ┌───────────────────────────────────────┐
       │ independent post-tune validation      │
       │ step / multi-speed / trajectory       │
       └───────────────────┬───────────────────┘
                           ▼
              ┌────────────────────────┐
              │ report / recommendation │
              └────────────────────────┘
```

---

# 95. 一句话理解整个项目

> **Simulink 负责“飞机怎么动”，ArduPlane 负责“飞控怎么控制并怎么 Native AUTOTUNE”，MATLAB 负责“把两边组织成可重复、可检查、可追溯的自动试验”。**

只要始终保持这三个职责边界清楚，工程就不会再次退回到“MATLAB 直接给角度、Simulink 自己控、最后却不知道真实飞控到底做了什么”的状态。
