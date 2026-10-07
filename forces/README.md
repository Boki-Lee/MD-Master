# forces/ —— 各种自定义力（tclForces）写法参考

跑生产模拟（步骤 **4prod**）时，用 NAMD 的 `tclForces` 给离子施加各种自定义力/电场。
这里的脚本都是**可直接复制**的模板，复制到项目的 `4prod/` 目录后用 `tclForcesScript` 挂上。

## 文件清单

| 文件 | 是什么 | 何时用 |
|---|---|---|
| `field_axial_tri.tcl` | 轴向**三角波**电压（0→+Vmax→−Vmax→0），空间均匀。**入门范例**，逻辑最简单。 | 测轴向 I-V 曲线，最简单加电场场景 |
| `field_axial_dc_radial_tri.tcl` | 轴向**恒定**电压 + 径向 **1/r 三角波**电压。**进阶范例**，含坐标获取、最小镜像、1/r 截断、离线自检，注释最全。 | 需要径向电场、或同时驱动轴向+径向 |
| `selftest_field.tcl` | 上面径向脚本的**离线自检**（`tclsh` 跑，不需要 NAMD）。核对波形/力方向/量级。 | 改完参数后先跑一遍确认公式正确 |
| `_template.tcl` | **新力写法骨架**：照着抄改参数区、初始化、`calcforces` 三块即可。 | 写一种全新的力 |

## 怎么用

1. 把要用的脚本复制进项目的 `4prod/`（例如 `cp forces/field_axial_tri.tcl 项目/4prod/`）。
2. 在 `4prod/prod.conf` 里写：

```tcl
tclForces        on
tclForcesScript  field_axial_tri.tcl
```

3. 若只想覆盖参数（不改脚本），用块形式：

```tcl
tclForcesScript {
    set ionFile "../1model/ion_ids.dat"
    set vmax 8.0
    source ./field_axial_tri.tcl
}
```

4. **改完先离线自检**（不需要 NAMD）：

```bash
tclsh selftest_field.tcl [../3eq/eq.restart.xsc]
```

## 数据文件约定（脚本里已写死相对路径）

| 文件 | 相对路径（相对 `4prod/`） | 内容 |
|---|---|---|
| 离子列表 | `../1model/ion_ids.dat` | 每行：离子ID 电荷 名称（**ID 从 0 开始**） |
| 盒子尺寸 | `../3eq/eq.restart.xsc` | 读 z 方向盒子长度（读不到用脚本内兜底值） |

## 写新力时的关键规矩（详见 `_template.tcl` 头注释）

1. 拿坐标：顶层 `addatom $id` 登记 → `calcforces` 里 `loadcoords p`。
2. 热路径（`calcforces`）不要调 proc，表达式全部内联。
3. 跨周期边界用**最小镜像**折回。
4. `1/r`、`1/r²` 场在 `r→0` 会发散，必须截断。
5. 力要有界、别 NaN；给所有读文件的数值兜底。
6. 改完跑 `tclsh selftest_field.tcl` 核对。

> 更完整的方法（坐标获取、性能、续算日志不截断、物理陷阱）见顶层 `WORKFLOW.md` 与
> `field_axial_dc_radial_tri.tcl` 头部注释。
