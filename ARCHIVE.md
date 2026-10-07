# ARCHIVE.md —— 「存入参考库」归档流程

> 项目跑完后，用户说"**把这个存入参考库 / 存入参考库 / 归档 / 存库**"时，按本文件走。
> 目的：把项目里**可复用**的部分收进本 skill 根目录，并**不漏地更新所有联动点**。
>
> 一句话原则：**入库的是可复用模板，不是运行产物**。
> 大轨迹 / restart 留在项目（数据盘），README 里记路径即可。

---

## 一、归档流程（6 步）

### 第 1 步：问清楚存什么（分类，必问）

问用户这个项目要收进库的是哪几样（可多选）：

| 代号 | 内容 | 落到 |
|---|---|---|
| A | 新模型 | `models/<name>/`（0build/1model/2min/3eq 的可复用部分） |
| B | 新自定义力 | `forces/` |
| C | 新分析脚本 | `analysis/` |
| D | 自由能改动 | `free_energy/<smd\|extract\|us\|pmf>/` |
| E | 新力场参数 | `forcefield/` |
| F | 新踩坑/经验 | `WORKFLOW.md`（必要时全局 `~/.dsh/AGENTS.md`） |

同时问：**项目路径在哪**；哪些产物留、哪些只记路径。

### 第 2 步：提取（只复制可复用件，排除大文件）

- 复制：`.tcl/.sh/.py`、`*.conf`、`*.psf/*.pdb`（模型级）、`ion_ids.dat`、`system_solv.log` 等小文件。
- **绝不复制** `*.dcd / *.coor / *.vel / 大 log`；在 README 里记下它们在数据盘的位置。
- 改 conf/脚本里的相对路径到新库结构（`../1model`、`../3eq`、`../forcefield`、`../4prod` 等）。
- 复制前**查重**：目标已存在同名文件就 diff，问用户"覆盖 or 另存 `<name>_v2`"。

### 第 3 步：写/补说明

- 新模型：写 `models/<name>/README.md`（盒子尺寸 / 原子数 / 离子种类与盐浓度 / 关键参数 / 相对路径约定）。
- 新力 / 新分析 / 新自由能：补对应 README 的「文件清单」表 + 「哪些要改」说明。

### 第 4 步：更新联动点（"那些要改"，见下表）

### 第 5 步：权限 + 校验

- `chmod +x` 新脚本（`*.sh` / `*.py` / selftest）。
- 跑对应校验：`check_setup.py` / `check_setup_us.py` / `tclsh selftest_field.tcl` / 语法检查。
- grep 确认无大轨迹、无旧目录引用残留。

### 第 6 步：停一下让用户确认（同样双重确认：两次通过才收尾），再收尾。

---

## 二、"那些要改"联动清单（核心）

库是多处交叉引用的，只复制文件不改联动点，会导致 `new_project.sh` 复制不到、
`README.md` 索引失真、子库 README 缺行。按下表逐条打勾：

| 存了什么 | 必改的联动点 |
|---|---|
| **新模型** `models/<name>/` | ① 写 `models/<name>/README.md`；② 顶层 `README.md` 索引 `models/` 下加一条；③ 若引入了新脚本，更新 `new_project.sh` 第 67 行（标准建模清单）或第 88–89 行（US 建模清单）；④ `WORKFLOW.md`（如有新坑/新模型入口） |
| **新自定义力** `forces/xxx.tcl` | ① `forces/README.md` 文件清单表加一行；② 顶层 `README.md` 的 `forces/` 条目；③ `new_project.sh` 第 76 行用 `*.tcl` 通配，**一般不用改**；④ 若需离线自检，新建/更新 selftest |
| **新分析脚本** `analysis/xxx.py` | ① `analysis/README.md` 文件清单表加一行；② 顶层 `README.md` 的 `analysis/` 条目；③ `new_project.sh` 第 101–102 行清单加文件名；④ 新增公共依赖时确认是否并入 `field_protocol.py` 或加进清单 |
| **自由能改动** `free_energy/<sub>/` | ① `free_energy/README.md`；② 顶层 `README.md` 的 `free_energy/` 条目；③ `new_project.sh` 第 84 行子目录列表（新增子目录才改） |
| **新力场参数** `forcefield/xxx` | ① 顶层 `README.md` 的 `forcefield/` 条目；② 相关模型 README/conf 的 `parameters` 引用（如需） |
| **新踩坑/经验** | ① `WORKFLOW.md` 对应章节（§8 坑 / §9 物理 / §10 排错 / §11 命令）；② 通用经验同步到全局 `~/.dsh/AGENTS.md` §踩坑 |

---

## 三、归档示例

### 例 1：把某个项目的径向力脚本归档到 `forces/`

1. 第 1 步 → 用户答 B（新自定义力），项目路径 `/mnt/data2/lbj/CNT/CNT1`。
2. 第 2 步 → 复制 `4prod/field_xxx.tcl` → `forces/field_xxx.tcl`；改里面 `../ion_ids.dat` 等路径为新结构。
3. 第 3 步 → `forces/README.md` 文件清单表加一行，写清用途/参数。
4. 第 4 步 → 顶层 `README.md` 的 `forces/` 条目加一行；`new_project.sh` 无需改（`*.tcl` 通配）。
5. 第 5 步 → `chmod 644`（.tcl 由 namd3 读，不需执行位）；`tclsh` 跑 selftest。
6. 第 6 步 → 确认。

### 例 2：归档一个跑完的项目为新模型

1. 第 1 步 → 用户答 A，项目 `/mnt/data2/.../proj`。
2. 第 2 步 → 建 `models/<name>/`，复制 `0build/*.tcl/.sh/.py`、`1model/*.psf/pdb + ion_ids.dat + system_solv.log`、
   `2min/min.conf`、`3eq/eq.conf`；**不复制 dcd/coor/vel**；改 conf 相对路径。
3. 第 3 步 → 写 `models/<name>/README.md`（参数表 + 相对路径约定）。
4. 第 4 步 → 顶层 `README.md` 索引加 `models/<name>/` 条目；如引入了新建模脚本，更新 `new_project.sh` 清单。
5. 第 5 步 → `python3 0build/check_setup.py`；grep 无大轨迹。
6. 第 6 步 → 确认。

> 机械复制可用 `archive_model.sh`（见下）代劳，跑完它打印"还需手动改"清单兜底。

---

## 四、辅助脚本 `archive_model.sh`

用法：

```bash
bash archive_model.sh /路径/跑完的项目 models/新模型名
```

- 复制 `0build` 脚本 + `1model` 小文件 + `2min`/`3eq` conf（**自动排除 dcd/coor/vel/大 log**）。
- 若项目用的是旧目录名（`min/`、`eq/`、`prod/`、产物在根目录），脚本会尽量映射并提示。
- 结束后**打印待办清单**（写模型 README、更新顶层 README 索引、更新 new_project.sh、跑校验），
  防止漏掉第 3/4/5 步。
