# LOW_LEVEL_DESIGN

## DiffEngine

目标：计算输入框旧文本与新文本之间的最小增量操作。

### DeltaOp

- `APPEND`
- `INSERT`
- `DELETE`
- `REPLACE`
- `FULL_SYNC`
- `NO_CHANGE`

### TextDelta 字段

- `op`
- `position`
- `deleteCount`
- `text`
- `clipboardHint`

### 算法

使用前缀 + 后缀匹配，时间复杂度 `O(N)`：

1. 计算最长公共前缀长度 `prefixLen`
2. 计算最长公共后缀长度 `suffixLen`（不与前缀重叠）
3. 计算 `deletedLen = old.length - prefixLen - suffixLen`
4. 计算 `insertedText = new.substring(prefixLen, new.length - suffixLen)`
5. 规则判定：
   - `old` 为空且 `new` 非空：`APPEND`
   - `new` 为空且 `old` 非空：`DELETE`（从 `position=0` 删除全部）
   - 完全相同：`NO_CHANGE`
   - 变化超过原文本 `60%`（且 `old.length > 5`）：`FULL_SYNC`
   - 仅插入：`APPEND`（插入点在末尾）或 `INSERT`（中间）
   - 仅删除：`DELETE`
   - 同时删除+插入：`REPLACE`
6. `clipboardHint = true` 当 `text.length > 10`

## 测试场景

- A: 拼音逐字输入 `你好世界`
- B: 语音整句一次输入（15+）
- C: 候选词替换 `北京 -> 南京`
- D: 自动补全 `苹 -> 苹果`
- E1: 尾删
- E2: 中删
- F: 全选替换（变化 >60% -> `FULL_SYNC`）
- G: 中间插入
