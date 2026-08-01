#!/bin/bash
#
# DecryptPrompt 论文分类索引工具 (高效版)
#
# 用法:
#   ./paper_index.sh                    # 生成完整索引 (Markdown)
#   ./paper_index.sh --stats            # 仅输出统计信息
#   ./paper_index.sh --search "RLHF"    # 搜索包含关键词的论文
#   ./paper_index.sh --category RLHF    # 查看特定分类的论文列表
#   ./paper_index.sh -o index.md        # 保存索引到文件
#   ./paper_index.sh --dedup            # 检测重复论文
#   ./paper_index.sh --dedup-report     # 生成详细去重报告
#   ./paper_index.sh --dedup-auto       # 自动去重(安全模式)
#

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_FILE="$BASE_DIR/.paper_cache.txt"
DEDUP_CACHE="$BASE_DIR/.dedup_cache.txt"
DEDUP_TRASH="$BASE_DIR/.dedup_trash"
DEDUP_REPORT="$BASE_DIR/DEDUP_REPORT.md"

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ============================================
# 更新缓存 (仅当目录有变化时)
# ============================================
update_cache() {
    local needs_update=false
    
    if [ ! -f "$CACHE_FILE" ]; then
        needs_update=true
    else
        # 检查缓存是否过期 (1小时)
        local cache_age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
        if [ $cache_age -gt 3600 ]; then
            needs_update=true
        fi
    fi
    
    if [ "$needs_update" = true ]; then
        echo -e "  ${YELLOW}🔍 构建索引缓存...${NC}" >&2
        
        # 使用高效的 find + awk 组合
        find "$BASE_DIR" -type f -name "*.pdf" \
            ! -path "*/.git/*" ! -path "*/.codegraph/*" \
            ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
            -printf "%h|%f\n" 2>/dev/null | \
        awk -F'|' -v base="$BASE_DIR/" '{
            path = $1
            gsub(base, "", path)
            n = split(path, parts, "/")
            category = parts[1]
            subcategory = (n > 2) ? parts[2] : "_root"
            gsub(/\.pdf$/i, "", $2)
            print category "|" subcategory "|" $2 "|" path "/" $2 ".pdf"
        }' > "$CACHE_FILE"
        
        echo -e "  ${GREEN}✅ 缓存已更新 ($(wc -l < "$CACHE_FILE") 篇论文)${NC}" >&2
    fi
}

# ============================================
# 统计信息
# ============================================
show_stats() {
    local total=$(wc -l < "$CACHE_FILE")
    
    echo ""
    echo "============================================================"
    echo -e "  ${BLUE}📊 DecryptPrompt 论文库统计${NC}"
    echo "============================================================"
    echo ""
    echo -e "  总论文数: ${GREEN}${total}${NC}"
    echo ""
    echo -e "  ${YELLOW}📈 论文数量 TOP 15 分类:${NC}"
    echo "  --------------------------------------------------------"
    
    cut -d'|' -f1 "$CACHE_FILE" | sort | uniq -c | sort -rn | head -15 | \
    awk '{printf "  %-28s %4s ", $2, $1; for(i=0;i<$1/5&&i<30;i++) printf "█"; print ""}'
    
    echo ""
    echo -e "  ${YELLOW}📂 全部分类 (${total} 篇):${NC}"
    echo "  --------------------------------------------------------"
    cut -d'|' -f1 "$CACHE_FILE" | sort | uniq -c | sort -rn | \
    awk '{printf "  %-30s %4s 篇\n", $2, $1}'
}

# ============================================
# 搜索论文
# ============================================
search_papers() {
    local query="$1"
    
    echo ""
    echo -e "  🔍 搜索 '${YELLOW}${query}${NC}'..."
    echo ""
    
    grep -i "|.*${query}" "$CACHE_FILE" 2>/dev/null | head -50 | \
    while IFS='|' read -r cat subcat name path; do
        [ "$subcat" = "_root" ] || subcat="/${subcat}"
        echo -e "  [${BLUE}${cat}${subcat}${NC}] ${name}"
        echo "     → ${path}"
        echo ""
    done
    
    local count=$(grep -ci "|.*${query}" "$CACHE_FILE" 2>/dev/null || echo 0)
    [ "$count" -gt 50 ] && echo "  ... (显示前 50 条，共 ${count} 条结果)"
}

# ============================================
# 显示特定分类
# ============================================
show_category() {
    local category="$1"
    
    if ! grep -q "^${category}|" "$CACHE_FILE"; then
        echo -e "  ${RED}❌ 未找到分类: ${category}${NC}"
        echo ""
        echo "  可用分类:"
        cut -d'|' -f1 "$CACHE_FILE" | sort -u | sed 's/^/    • /'
        return
    fi
    
    local total=$(grep -c "^${category}|" "$CACHE_FILE")
    
    echo ""
    echo -e "  📁 分类: ${GREEN}${category}${NC} (${total} 篇)"
    echo "  --------------------------------------------------------"
    echo ""
    
    grep "^${category}|" "$CACHE_FILE" | cut -d'|' -f2 | sort -u | while read subcat; do
        local display="${subcat}"
        [ "$subcat" = "_root" ] && display="根目录"
        
        local sub_count=$(grep -c "^${category}|${subcat}|" "$CACHE_FILE")
        echo -e "  [${YELLOW}${display}${NC}] (${sub_count} 篇)"
        
        grep "^${category}|${subcat}|" "$CACHE_FILE" | cut -d'|' -f3- | sed 's/^/    • /'
        echo ""
    done
}

# ============================================
# 生成 Markdown 索引
# ============================================
generate_markdown() {
    local output_file="$1"
    local total=$(wc -l < "$CACHE_FILE")
    local date_str=$(date '+%Y-%m-%d %H:%M')
    
    {
        echo "# DecryptPrompt 论文索引"
        echo ""
        echo "> 自动生成于 **${date_str}** | 共 **${total}** 篇论文"
        echo ""
        echo "## 📊 分类统计"
        echo ""
        echo "| # | 分类 | 论文数 | 占比 |"
        echo "|---|------|--------|------|"
        
        cut -d'|' -f1 "$CACHE_FILE" | sort | uniq -c | sort -rn | \
        awk -v total="$total" '{
            pct = sprintf("%.1f", $1/total*100)
            NR++
            printf "| %d | \`%s\` | %d | %s%% |\n", NR, $2, $1, pct
        }'
        
        echo ""
        echo "---"
        echo ""
        echo "## 📁 详细索引"
        echo ""
        
        cut -d'|' -f1 "$CACHE_FILE" | sort -u | while read category; do
            local cat_total=$(grep -c "^${category}|" "$CACHE_FILE")
            
            echo "### ${category}"
            echo ""
            echo "**共 ${cat_total} 篇论文**"
            echo ""
            
            grep "^${category}|" "$CACHE_FILE" | cut -d'|' -f2 | sort -u | while read subcat; do
                if [ "$subcat" = "_root" ]; then
                    echo "<details>"
                    echo "<summary>📄 根目录</summary>"
                else
                    local sub_count=$(grep -c "^${category}|${subcat}|" "$CACHE_FILE")
                    echo "<details>"
                    echo "<summary>📂 ${subcat} (${sub_count})</summary>"
                fi
                echo ""
                echo "| 论文 | 路径 |"
                echo "|------|------|"
                
                grep "^${category}|${subcat}|" "$CACHE_FILE" | \
                while IFS='|' read -r c s rest; do
                    local name=$(echo "$rest" | cut -d'|' -f1)
                    local path=$(echo "$rest" | cut -d'|' -f2)
                    echo "| ${name} | \`${path}\` |"
                done
                
                echo ""
                echo "</details>"
                echo ""
            done
            
            echo "---"
            echo ""
        done
    } > "${output_file:-/dev/stdout}"
    
    if [ -n "$output_file" ]; then
        echo -e "  ${GREEN}✅ 索引已保存到: ${output_file}${NC}" >&2
    fi
}

# ============================================
# 论文去重功能
# ============================================

# 计算文件MD5 (使用缓存加速)
get_md5() {
    local file="$1"
    local md5_cache="$BASE_DIR/.md5_cache"

    if [ -f "$md5_cache" ]; then
        # 转义路径中的特殊字符
        local escaped_file=$(echo "$file" | sed 's/[\/&]/\\&/g')
        local cached=$(grep "|${escaped_file}$" "$md5_cache" 2>/dev/null | tail -1 | cut -d'|' -f1)
        if [ -n "$cached" ]; then
            echo "$cached"
            return
        fi
    fi

    # 使用 PowerShell 计算MD5 (Windows兼容)
    local md5=$(powershell -NoProfile -Command "Get-FileHash '$(pwd)/$file' -Algorithm MD5 | Select-Object -ExpandProperty Hash" 2>/dev/null | tr -d '\r\n')

    if [ -n "$md5" ] && [ ${#md5} -eq 32 ]; then
        echo "${md5}|${file}" >> "$md5_cache"
        echo "$md5"
    else
        # 返回空字符串表示失败
        echo ""
    fi
}

# 检测重复论文 (基于文件大小 + MD5双重验证)
detect_duplicates() {
    echo ""
    echo -e "  ${YELLOW}🔍 检测重复论文...${NC}"
    echo ""

    local temp_sizes=$(mktemp)

    # 第一步: 基于文件大小查找可能的重复
    find "$BASE_DIR" -type f -name "*.pdf" \
        ! -path "*/.git/*" ! -path "*/.codegraph/*" \
        ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
        -printf "%s|%p\n" 2>/dev/null | sort -t'|' -k1 -n > "$temp_sizes"

    # 找出相同大小的文件对
    local potential=0
    local confirmed=0
    local total_wasted=0

    # 读取文件并检测重复
    local prev_size=""
    local prev_path=""

    echo -e "  ${CYAN}正在分析文件... (这可能需要几分钟)${NC}"
    echo ""

    while IFS='|' read -r size path; do
        [ -z "$size" ] && continue

        if [ -n "$prev_size" ] && [ "$size" = "$prev_size" ] && [ "$size" -gt 10000 ]; then
            potential=$((potential + 1))

            # 计算两个文件的MD5
            local md5_prev=$(get_md5 "$prev_path")
            local md5_curr=$(get_md5 "$path")

            if [ -n "$md5_prev" ] && [ -n "$md5_curr" ] && [ "$md5_prev" = "$md5_curr" ]; then
                confirmed=$((confirmed + 1))
                total_wasted=$((total_wasted + size))

                local rel_prev="${prev_path#$BASE_DIR/}"
                local rel_curr="${path#$BASE_DIR/}"
                local prev_cat=$(echo "$rel_prev" | cut -d'/' -f1)
                local curr_cat=$(echo "$rel_curr" | cut -d'/' -f1)
                local human_size=$(echo "scale=1; $size / 1048576" | awk '{printf "%.1f MB", $1}' 2>/dev/null || echo "$((size/1024)) KB")

                echo -e "  ${RED}[重复 #${confirmed}]${NC}"
                echo -e "     文件: $(basename "$path" .pdf)"
                echo -e "     大小: ${human_size}"
                echo -e "     MD5:  ${md5_prev}"
                echo ""
                echo -e "     A: ${GREEN}${rel_prev}${NC} [${prev_cat}]"
                echo -e "     B: ${rel_curr} [${curr_cat}]"
                echo ""
            fi
        fi

        prev_size="$size"
        prev_path="$path"
    done < "$temp_sizes"

    rm -f "$temp_sizes"

    echo "  --------------------------------------------------------"
    echo -e "  检测结果:"
    echo -e "  • 可能重复 (同大小): ${potential} 组"
    echo -e "  • 确认重复 (同MD5):   ${GREEN}${confirmed} 组${NC}"
    echo -e "  • 可释放空间:         ~$(echo "scale=2; $total_wasted / 1048576" | awk '{printf "%.2f MB", $1}' 2>/dev/null || echo "$((total_wasted/1048576)) MB")"
    echo ""
    echo -e "  提示: 运行 ${CYAN}./paper_index.sh --dedup-report${NC} 生成详细报告"
    echo -e "       运行 ${CYAN}./paper_index.sh --dedup-auto${NC} 自动清理"
    echo ""
}

# 生成详细去重报告
generate_dedup_report() {
    echo ""
    echo -e "  ${CYAN}📝 生成去重报告...${NC}"

    local report_file="$DEDUP_REPORT"
    local temp_data=$(mktemp)

    # 收集所有重复信息
    find "$BASE_DIR" -type f -name "*.pdf" \
        ! -path "*/.git/*" ! -path "*/.codegraph/*" \
        ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
        -printf "%s|%p\n" 2>/dev/null | sort -t'|' -k1 -n > "$temp_data"

    # 开始写报告
    {
        echo "# DecryptPrompt 论文去重报告"
        echo ""
        echo "> 自动生成于 **$(date '+%Y-%m-%d %H:%M')**"
        echo ""
        echo "---"
        echo ""

        # 分析重复
        local group_num=0
        local total_dup=0
        local total_size=0
        local prev_size=""
        local prev_path=""

        echo "## 📊 重复概览" > /dev/null
        # 将在循环中统计

        while IFS='|' read -r size path; do
            [ -z "$size" ] && continue

            if [ -n "$prev_size" ] && [ "$size" = "$prev_size" ] && [ "$size" -gt 10000 ]; then
                # 计算MD5验证
                local md5_prev=$(get_md5 "$prev_path")
                local md5_curr=$(get_md5 "$path")

                if [ -n "$md5_prev" ] && [ -n "$md5_curr" ] && [ "$md5_prev" = "$md5_curr" ]; then
                    group_num=$((group_num + 1))
                    total_dup=$((total_dup + 2))
                    total_size=$((total_size + size))

                    local rel_prev="${prev_path#$BASE_DIR/}"
                    local rel_curr="${path#$BASE_DIR/}"
                    local filename=$(basename "$path" .pdf)
                    local prev_cat=$(echo "$rel_prev" | cut -d'/' -f1)
                    local curr_cat=$(echo "$rel_curr" | cut -d'/' -f1)
                    local human_size=$(awk "BEGIN{printf \"%.1f MB\", $size/1048576}")

                    echo "### 🔖 重复组 #${group_num}: ${filename}"
                    echo ""
                    echo "**大小**: ${human_size} | **MD5**: \`${md5_prev}\`"
                    echo ""
                    echo "| # | 文件路径 | 分类 | 建议 |"
                    echo "|---|----------|------|------|"

                    # 判断哪个路径更合适保留 (更短的路径优先)
                local prev_depth=$(echo "$rel_prev" | tr -cd '/' | wc -c)
                    local curr_depth=$(echo "$rel_curr" | tr -cd '/' | wc -c)

                if [ "$prev_depth" -le "$curr_depth" ]; then
                    echo "| ✅ | \`${rel_prev}\` | ${prev_cat} | **保留** |"
                    echo "| ❌ | \`${rel_curr}\` | ${curr_cat} | 可删除 |"
                else
                    echo "| ❌ | \`${rel_prev}\` | ${prev_cat} | 可删除 |"
                    echo "| ✅ | \`${rel_curr}\` | ${curr_cat} | **保留** |"
                fi
                echo ""
            fi
        fi

        prev_size="$size"
        prev_path="$path"
    done < "$temp_data"

    echo "---"
    echo ""
    echo "## 📈 统计汇总"
    echo ""
    echo "| 指标 | 数值 |"
    echo "|------|------|"
    echo "| 确认重复组数 | ${group_num} |"
    echo "| 涉及文件数 | ${total_dup} |"
    echo "| 可释放空间 | ~$(awk "BEGIN{printf \"%.2f MB\", $total_size/1048576}") |"
    echo ""
    echo "---"
    echo ""
    echo "## 🛠️ 操作建议"
    echo ""
    echo '```bash'
    echo "# 查看重复详情"
    echo "./paper_index.sh --dedup"
    echo ""
    echo "# 自动清理 (移动到回收站)"
    echo "./paper_index.sh --dedup-auto"
    echo ""
    echo "# 查看回收站"
    echo "./paper_index.sh --restore"
    echo ""
    echo "# 确认后永久删除"
    echo "rm -rf .dedup_trash/"
    echo '```'
    echo ""
    echo "> ⚠️ **注意**: 去重基于文件内容(MD5哈希)，不同版本的同名论文不会被删除。"
    echo "> 建议先查看报告确认无误后再执行自动清理。"

    } > "$report_file"

    rm -f "$temp_data"

    echo -e "  ${GREEN}✅ 报告已保存到: ${report_file}${NC}"
    echo ""
}

# 自动去重 (安全模式: 移动到回收站目录)
auto_dedup() {
    echo ""
    echo -e "  ${RED}⚠️  自动去重模式${NC}"
    echo -e "  重复文件将移动到 ${YELLOW}.dedup_trash/${NC} 目录"
    echo -e "  可使用 ${CYAN}--restore${NC} 命令恢复"
    echo ""
    read -p "  是否继续? (y/N): " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { echo "  已取消"; return; }

    # 创建回收站目录
    mkdir -p "$DEDUP_TRASH"

    local moved=0
    local freed=0
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="$DEDUP_TRASH/dedup_${timestamp}.log"

    echo "# 去重操作日志 - $(date)" > "$log_file"
    echo "" >> "$log_file"

    # 收集所有PDF并排序
    local temp_data=$(mktemp)
    find "$BASE_DIR" -type f -name "*.pdf" \
        ! -path "*/.git/*" ! -path "*/.codegraph/*" \
        ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
        -printf "%s|%p\n" 2>/dev/null | sort -t'|' -k1 -n > "$temp_data"

    local prev_size=""
    local prev_path=""

    while IFS='|' read -r size path; do
        [ -z "$size" ] && continue

        if [ -n "$prev_size" ] && [ "$size" = "$prev_size" ] && [ "$size" -gt 10000 ]; then
            # MD5验证
            local md5_prev=$(get_md5 "$prev_path")
            local md5_curr=$(get_md5 "$path")

            if [ -n "$md5_prev" ] && [ -n "$md5_curr" ] && [ "$md5_prev" = "$md5_curr" ]; then
                # 决定保留哪个 (路径更短/更浅的优先)
                local rel_prev="${prev_path#$BASE_DIR/}"
                local rel_curr="${path#$BASE_DIR/}"
                local prev_depth=$(echo "$rel_prev" | tr -cd '/' | wc -c)
                local curr_depth=$(echo "$rel_curr" | tr -cd '/' | wc -c)

                local keep_path remove_path
                if [ "$prev_depth" -le "$curr_depth" ]; then
                    keep_path="$prev_path"
                    remove_path="$path"
                else
                    keep_path="$path"
                    remove_path="$prev_path"
                fi

                # 执行移动
                local dest="$DEDUP_TRASH/${timestamp}_$(basename "$remove_path")"
                mv "$remove_path" "$dest" 2>/dev/null

                if [ $? -eq 0 ]; then
                    moved=$((moved + 1))
                    freed=$((freed + size))

                    local rel_remove="${remove_path#$BASE_DIR/}"
                    local rel_keep="${keep_path#$BASE_DIR/}"

                    echo "[MOVED] ${rel_remove}" >> "$log_file"
                    echo "[KEEP]  ${rel_keep}" >> "$log_file"
                    echo "" >> "$log_file"

                    echo -e "  ${GREEN}✓${NC} 移动: ${rel_remove}"
                    echo -e "     保留: ${rel_keep}"
                fi
            fi
        fi

        prev_size="$size"
        prev_path="$path"
    done < "$temp_data"

    rm -f "$temp_data"

    echo ""
    echo -e "  ${GREEN}🎉 去重完成!${NC}"
    echo -e "  移动文件: ${moved} 个"
    echo -e "  释放空间: ~$(awk "BEGIN{printf \"%.2f MB\", $freed/1048576}")"
    echo -e "  日志文件: ${log_file}"
    echo -e "  回收站:   ${DEDUP_TRASH}/"
    echo ""
    echo -e "  ${YELLOW}提示:${NC}"
    echo -e "  • 运行 ${CYAN}./paper_index.sh --restore${NC} 查看回收站"
    echo -e "  • 确认后运行: rm -rf ${DEDUP_TRASH}/"
    echo ""

    # 刷新缓存
    rm -f "$CACHE_FILE"
}

# 恢复从回收站的文件
restore_from_trash() {
    if [ ! -d "$DEDUP_TRASH" ]; then
        echo -e "  ${RED}❌ 回收站目录不存在${NC}"
        return
    fi

    local files=$(find "$DEDUP_TRASH" -name "*.pdf" -type f 2>/dev/null | wc -l)
    local logs=$(find "$DEDUP_TRASH" -name "*.log" -type f 2>/dev/null | wc -l)

    echo ""
    echo -e "  ${CYAN}📦 回收站状态${NC}"
    echo "  --------------------------------------------------------"
    echo -e "  PDF 文件: ${files} 个"
    echo -e "  日志文件: ${logs} 个"
    echo ""

    if [ "$files" -gt 0 ]; then
        echo -e "  ${YELLOW}回收站中的文件:${NC}"
        echo ""
        find "$DEDUP_TRASH" -name "*.pdf" -type f 2>/dev/null | while read -r f; do
            local name=$(basename "$f")
            local size=$(du -h "$f" 2>/dev/null | cut -f1)
            # 提取原始文件名 (去掉时间戳前缀)
            local orig_name=$(echo "$name" | sed 's/^[0-9_]*//')
            echo "  • ${orig_name} (${size})"
        done
        echo ""
        echo -e "  ${YELLOW}手动恢复方法:${NC}"
        echo "  1. 查看 .dedup_trash/ 中的日志了解原始位置"
        echo "  2. 手动将文件移动回原位置"
    else
        echo -e "  ${GREEN}回收站为空${NC}"
    fi
    echo ""
}

# ============================================
# 论文相似度检测与智能去重
# ============================================

SIMILARITY_CACHE="$BASE_DIR/.similarity_cache.txt"
SIMILARITY_REPORT="$BASE_DIR/SIMILARITY_REPORT.md"

# 标准化文件名 (用于比较)
normalize_filename() {
    local name="$1"
    # 转小写
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    # 移除常见标点和特殊字符
    name=$(echo "$name" | sed 's/[.,:;!?(){}\[\]'"'"'-]//g')
    # 压缩多个空格为单个空格
    name=$(echo "$name" | tr -s ' ')
    # 去除前后空格
    name=$(echo "$name" | sed 's/^[ \t]*//;s/[ \t]*$//')
    echo "$name"
}

# 计算两个字符串的 Jaccard 相似度 (基于词级别)
jaccard_similarity() {
    local str1="$1"
    local str2="$2"

    # 分词并转为集合
    local words1=$(echo "$str1" | tr ' ' '\n' | sort -u | grep -v '^$')
    local words2=$(echo "$str2" | tr ' ' '\n' | sort -u | grep -v '^$')

    local count1=$(echo "$words1" | wc -l)
    local count2=$(echo "$words2" | wc -l)

    # 计算交集
    local intersect=$(comm -12 <(echo "$words1") <(echo "$words2") 2>/dev/null | wc -l)
    # 计算并集
    local union=$(comm -13 <(echo "$words1") <(echo "$words2") 2>/dev/null | wc -l)
    union=$((union + intersect))

    if [ $union -eq 0 ]; then
        echo "0"
    else
        awk "BEGIN {printf \"%.3f\", $intersect/$union}"
    fi
}

# 提取PDF文本 (用于内容相似度比较)
extract_pdf_text() {
    local pdf_file="$1"
    local text_cache="$BASE_DIR/.pdf_text_cache"

    # 检查缓存
    local cache_key=$(echo "$pdf_file" | md5sum | cut -d' ' -f1)
    local cached_text=$(grep "^${cache_key}|" "$text_cache" 2>/dev/null | cut -d'|' -f2-)

    if [ -n "$cached_text" ]; then
        echo "$cached_text"
        return
    fi

    local text=""

    # 尝试使用 pdftotext (poppler工具包)
    if command -v pdftotext &>/dev/null; then
        text=$(pdftotext "$pdf_file" - 2>/dev/null | head -100 | tr '\n' ' ')
    fi

    # 如果失败，尝试使用 Python
    if [ -z "$text" ] && command -v python3 &>/dev/null; then
        text=$(python3 -c "
import sys
try:
    import PyPDF2
    reader = PyPDF2.PdfReader('$pdf_file')
    text = ''
    for page in reader.pages[:5]:  # 只读前5页
        text += page.extract_text() or ''
    print(text[:2000])
except:
    pass
" 2>/dev/null)
    fi

    # 如果还是失败，尝试 PowerShell
    if [ -z "$text" ]; then
        text=$(powershell -NoProfile -Command "
try {
    \$pdf = New-Object System.Text.StringList
    \$reader = New-Object iTextSharp.text.pdf.PdfReader '$pdf_file'
    for (\$i = 0; \$i -lt [Math]::Min(5, \$reader.NumberOfPages); \$i++) {
        \$pdf.Add(\$reader.GetPageContent(\$i).ToString())
    }
    \$pdf.ToString().Substring(0, [Math]::Min(2000, \$pdf.ToString().Length))
} catch {}
" 2>/dev/null | tr -d '\r\n')
    fi

    # 缓存结果 (只缓存前500字符用于快速比较)
    if [ -n "$text" ]; then
        local short_text="${text:0:500}"
        echo "${cache_key}|${short_text}" >> "$text_cache"
        echo "$short_text"
    else
        echo ""
    fi
}

# 检测相似论文 (综合: 文件名 + 内容 + MD5)
detect_similar_papers() {
    echo ""
    echo -e "  ${CYAN}🔬 论文相似度深度分析${NC}"
    echo ""

    local temp_files=$(mktemp)
    local temp_results=$(mktemp)

    # 收集所有PDF文件信息
    find "$BASE_DIR" -type f -name "*.pdf" \
        ! -path "*/.git/*" ! -path "*/.codegraph/*" \
        ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
        -printf "%s|%p\n" 2>/dev/null > "$temp_files"

    local total=$(wc -l < "$temp_files")
    echo -e "  分析 ${total} 篇论文的相似度..."
    echo ""

    # 使用 awk 进行高效的两两比较
    awk -F'|' '
    BEGIN {
        threshold_name = 0.7   # 文件名相似度阈值
        threshold_size = 0.95  # 文件大小相似阈值
        dup_count = 0
        similar_count = 0
    }

    {
        size[NR] = $1
        path[NR] = $2
        filename[NR] = $2
        sub(/.*\//, "", filename[NR])
        sub(/\.pdf$/i, "", filename[NR])

        # 标准化文件名
        norm[NR] = tolower(filename[NR])
        gsub(/[,.:;!?(){}[\]'"'"'-]/, "", norm[NR])
        gsub(/  +/, " ", norm[NR])
        sub(/^ /, "", norm[NR])
        sub(/ $/, "", norm[NR])

        total = NR
    }

    END {
        for (i = 1; i <= total; i++) {
            for (j = i + 1; j <= total; j++) {
                # 检查目录信息（用于显示，不再跳过同目录）
                split(path[i], pi, "/")
                split(path[j], pj, "/")

                # 1. 大小完全相同的文件 (提示可能重复，需用 --dedup 验证MD5)
                if (size[i] == size[j] && size[i] > 10000) {
                    dup_count++
                    printf("SAMESIZE|%s|%s|%d|%s|%s\n",
                        path[i], path[j], size[i],
                        filename[i], filename[j])
                    continue
                }

                # 2. 文件名相似度计算 (Jaccard)
                n1 = split(norm[i], w1, " ")
                n2 = split(norm[j], w2, " ")

                # 使用简单数组模拟集合 (避免delete问题)
                inter = 0; union = 0

                # 统计词1中的唯一词
                for (k = 1; k <= n1; k++) {
                    found = 0
                    for (m = 1; m < k; m++) {
                        if (w1[m] == w1[k]) { found = 1; break }
                    }
                    if (!found) union++

                    # 检查是否在词2中
                    for (l = 1; l <= n2; l++) {
                        if (w1[k] == w2[l]) { inter++; break }
                    }
                }

                # 统计词2中的唯一词 (不在词1中)
                for (k = 1; k <= n2; k++) {
                    found = 0
                    for (m = 1; m < k; m++) {
                        if (w2[m] == w2[k]) { found = 1; break }
                    }
                    if (!found) {
                        in_w1 = 0
                        for (l = 1; l <= n1; l++) {
                            if (w2[k] == w1[l]) { in_w1 = 1; break }
                        }
                        if (!in_w1) union++
                    }
                }

                jaccard = (union > 0) ? inter / union : 0

                # 文件大小比率
                size_ratio = (size[i] > size[j]) ? size[j]/size[i] : size[i]/size[j]

                # 判断是否相似
                if (jaccard >= threshold_name && size_ratio >= threshold_size) {
                    similar_count++
                    reason = sprintf("名称相似:%.0f%% 大小比:%.0f%%", jaccard*100, size_ratio*100)
                    printf("SIMILAR|%.3f|%s|%s|%d|%s|%s|%s\n",
                        jaccard, path[i], path[j],
                        (size[i] + size[j]) / 2,
                        filename[i], filename[j], reason)
                }
            }
        }

        # 输出统计
        print "STATS:" total ":" dup_count ":" similar_count
    }
    ' "$temp_files" > "$temp_results"

    # 解析结果
    local stats_line=$(grep "^STATS:" "$temp_results")
    local stat_total=$(echo "$stats_line" | cut -d':' -f2)
    local stat_dup=$(echo "$stats_line" | cut -d':' -f3)
    local stat_similar=$(echo "$stats_line" | cut -d':' -f4)

    echo -e "  ${YELLOW}━━━ 分析结果 ━━━${NC}"
    echo ""
    echo -e "  总论文数:     ${stat_total:-0}"
    echo -e "  完全重复:     ${RED}${stat_dup:-0}${NC} 组 (大小相同，需用 --dedup 验证MD5)"
    echo -e "  高度相似:     ${YELLOW}${stat_similar:-0}${NC} 对 (名称+大小)"
    echo ""

    # 显示大小相同的文件
    local dups=$(grep "^SAMESIZE|" "$temp_results")
    if [ -n "$dups" ]; then
        echo -e "  ${RED}🔴 大小相同的论文 (可能重复，建议用 --dedup 验证):${NC}"
        echo "  ────────────────────────────────────────"

        echo "$dups" | head -10 | while IFS='|' read -r type p1 p2 size n1 n2; do
            local r1="${p1#$BASE_DIR/}"
            local r2="${p2#$BASE_DIR/}"
            local c1=$(echo "$r1" | cut -d'/' -f1)
            local c2=$(echo "$r2" | cut -d'/' -f1)
            printf "\n  ${RED}✗${NC} %s\n     A: [%s] %s\n     B: [%s] %s\n" \
                "${n1:0:60}" "$c1" "$r1" "$c2" "$r2"
        done

        local dup_more=$(echo "$dups" | wc -l)
        [ "$dup_more" -gt 10 ] && echo -e "\n  ... 还有 $((dup_more - 10)) 组 (查看完整报告)"
    fi

    # 显示高度相似
    local similars=$(grep "^SIMILAR|" "$temp_results")
    if [ -n "$similars" ]; then
        echo ""
        echo -e "  ${YELLOW}🟡 高度相似的论文 (可能是同一篇的不同版本):${NC}"
        echo "  ────────────────────────────────────────"

        echo "$similars" | sort -t'|' -k2 -rn | head -20 | while IFS='|' read -r sim score p1 p2 size n1 n2 reason; do
            local r1="${p1#$BASE_DIR/}"
            local r2="${p2#$BASE_DIR/}"
            local c1=$(echo "$r1" | cut -d'/' -f1)
            local c2=$(echo "$r2" | cut -d'/' -f1)
            local pct=$(awk "BEGIN{printf \"%.0f\", $score*100}")
            printf "\n  ${YELLOW}~${NC} [%s%%] %s\n     A: [%s] %s\n     B: [%s] %s\n     原因: %s\n" \
                "$pct" "${n1:0:50}" "$c1" "$r1" "$c2" "$r2" "$reason"
        done

        local sim_more=$(echo "$similars" | wc -l)
        [ "$sim_more" -gt 20 ] && echo -e "\n  ... 还有 $((sim_more - 20)) 对"
    fi

    rm -f "$temp_files" "$temp_results"

    echo ""
    echo -e "  提示: 运行 ${CYAN}./paper_index.sh --similarity-report${NC} 生成详细报告"
    echo "       运行 ${CYAN}./paper_index.sh --smart-dedup${NC} 执行智能去重"
    echo ""
}

# 生成详细相似度报告
generate_similarity_report() {
    echo ""
    echo -e "  ${CYAN}📝 生成相似度分析报告...${NC}"

    local temp_files=$(mktemp)
    local temp_results=$(mktemp)

    # 收集文件
    find "$BASE_DIR" -type f -name "*.pdf" \
        ! -path "*/.git/*" ! -path "*/.codegraph/*" \
        ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
        -printf "%s|%p\n" 2>/dev/null > "$temp_files"

    # 生成报告
    {
        echo "# 论文相似度分析报告"
        echo ""
        echo "> 自动生成于 **$(date '+%Y-%m-%d %H:%M')**"
        echo "> 基于 **文件名Jaccard相似度** + **文件大小对比** 的综合分析"
        echo ""
        echo "---"
        echo ""
        echo "## 📊 分析概览"
        echo ""
        echo "| 指标 | 数值 | 说明 |"
        echo "|------|------|------|"
        echo "| 总论文数 | $(wc -l < "$temp_files") | 排除 .git, .codegraph, PPTS 等 |"
        echo "| 分析方法 | 多维度 | 文件名标准化 + Jaccard相似度 + 大小比对 |"
        echo "| 名称相似阈值 | ≥70% | Jaccard系数 |"
        echo "| 大小相似阈值 | ≥95% | 文件大小比率 |"
        echo ""
        echo "---"
        echo ""

        # 执行分析
        awk -F'|' '
        {
            size[NR] = $1
            path[NR] = $2
            filename[NR] = $2
            sub(/.*\//, "", filename[NR])
            sub(/\.pdf$/i, "", filename[NR])

            norm[NR] = tolower(filename[NR])
            gsub(/[.,:;!?(){}[\]'"'"'-]/, "", norm[NR])
            gsub(/  +/, " ", norm[NR])
            sub(/^ /, "", norm[NR])
            sub(/ $/, "", norm[NR])
            total = NR
        }

        END {
            dup_count = 0
            sim_groups = 0
            sim_details = ""

            for (i = 1; i <= total; i++) {
                for (j = i + 1; j <= total; j++) {
                    split(path[i], pi, "/")
                    split(path[j], pj, "/")
                    if (pi[1] == pj[1]) continue

                    # Jaccard相似度 (使用简单数组避免delete语法问题)
                    split(norm[i], w1, " ")
                    split(norm[j], w2, " ")

                    # 计算交集和并集
                    inter = 0; union = 0
                    n1 = length(w1); n2 = length(w2)

                    # 统计词1中的唯一词
                    for (k = 1; k <= n1; k++) {
                        found = 0
                        for (m = 1; m < k; m++) { if (w1[m] == w1[k]) found = 1 }
                        if (!found) union++
                        for (l = 1; l <= n2; l++) { if (w1[k] == w2[l]) { inter++; break } }
                    }

                    # 统计词2中的唯一词 (不在词1中)
                    for (k = 1; k <= n2; k++) {
                        found = 0
                        for (m = 1; m < k; m++) { if (w2[m] == w2[k]) found = 1 }
                        if (!found) {
                            in_w1 = 0
                            for (l = 1; l <= n1; l++) { if (w2[k] == w1[l]) in_w1 = 1 }
                            if (!in_w1) union++
                        }
                    }

                    jaccard = (union > 0) ? inter / union : 0
                    size_ratio = (size[i] > size[j]) ? size[j]/size[i] : size[i]/size[j]

                    if (size[i] == size[j] && size[i] > 10000) {
                        dup_count++
                        ri = path[i]; sub(/.*\//, "", ri); sub(/\.pdf$/i, "", ri)
                        rj = path[j]; sub(/.*\//, "", rj); sub(/\.pdf$/i, "", rj)
                        ci = path[i]; sub(/.*\//, "", ci); ci = substr(ci, 1, index(ci, "/")-1)
                        cj = path[j]; sub(/.*\//, "", cj); cj = substr(cj, 1, index(cj, "/")-1)

                        print "DUP|" ri "|" rj "|" ci "|" cj "|" size[i]
                    } else if (jaccard >= 0.7 && size_ratio >= 0.95) {
                        sim_groups++
                        ri = path[i]; sub(/.*\//, "", ri); sub(/\.pdf$/i, "", ri)
                        rj = path[j]; sub(/.*\//, "", rj); sub(/\.pdf$/i, "", rj)
                        ci = path[i]; sub(/.*\//, "", ci); ci = substr(ci, 1, index(ci, "/")-1)
                        cj = path[j]; sub(/.*\//, "", cj); cj = substr(cj, 1, index(cj, "/")-1)

                        printf "SIM|%.0f%%|%s|%s|%s|%s|%s|%s\n",
                            jaccard*100, ri, rj, ci, cj,
                            (size[i]+size[j])/2, (size[i]==size[j])?"相同":"相近"
                    }
                }
            }

            print "STATS:" dup_count "|" sim_groups
        }
        ' "$temp_files" | sort > "$temp_results"

        local stats=$(grep "^STATS:" "$temp_results")
        local dups=$(echo "$stats" | cut -d'|' -f2)
        local sims=$(echo "$stats" | cut -d'|' -f3)

        echo "### 发现的问题"
        echo ""
        echo "| 类型 | 数量 | 建议 |"
        echo "|------|------|------|"
        echo "| 🔴 大小相同 | ${dups} 组 | 需用 --dedup 验证是否真重复 |"
        echo "| 🟡 高度相似 | ${sims} 对 | 需人工确认是否同一篇 |"
        echo ""
        echo "---"
        echo ""

        # 详细列表 - 完全重复
        if [ "$dups" -gt 0 ]; then
            echo "## 🔴 大小相同文件详情"
            echo ""
            echo "以下文件 **大小完全相同**，可能是重复文件 (需用 `--dedup` 验证MD5):"
            echo ""

            grep "^DUP|" "$temp_results" | while IFS='|' read -r type n1 n2 c1 c2 size; do
                echo "#### ${n1}"
                echo ""
                echo "| 属性 | 文件A | 文件B |"
                echo "|------|-------|-------|"
                echo "| 文件名 | \`${n1}\` | \`${n2}\` |"
                echo "| 所在分类 | \`${c1}\` | \`${c2}\` |"
                echo "| 文件大小 | $(awk "BEGIN{printf \"%.1f MB\", $size/1048576}") | 同上 |"
                echo "| 建议 | ⚠️ **需验证** | ⚠️ **需验证** |"
                echo ""
            done
        fi

        # 详细列表 - 高度相似
        if [ "$sims" -gt 0 ]; then
            echo "---"
            echo ""
            echo "## 🟡 高度相似文件详情"
            echo ""
            echo "以下文件 **名称和大小都非常相似**，可能是同一篇论文的不同版本:"
            echo ""

            grep "^SIM|" "$temp_results" | while IFS='|' read -r type score n1 n2 c1 c2 size sizerel; do
                echo "### ${n1} ≈ ${n2}"
                echo ""
                echo "| 属性 | 文件A | 文件B |"
                echo "|------|-------|-------|"
                echo "| 文件名 | \`${n1}\` | \`${n2}\` |"
                echo "| 所在分类 | \`${c1}\` | \`${c2}\` |"
                echo "| 名称相似度 | ${score} | - |"
                echo "| 平均大小 | $(awk "BEGIN{printf \"%.1f MB\", $size/1048576}") | - |"
                echo "| 大小关系 | - | ${sizerel} |"
                echo ""
                echo "**建议**: 请人工确认这两篇是否为同一篇论文。如果是，建议保留更规范的命名版本。"
                echo ""
            done
        fi

        echo "---"
        echo ""
        echo "## 🛠️ 操作指南"
        echo ""
        echo '```bash'
        echo "# 1. 查看去重建议 (不执行操作)"
        echo "./paper_index.sh --detect-similar"
        echo ""
        echo "# 2. 执行基础去重 (仅MD5相同的)"
        echo "./paper_index.sh --dedup-auto"
        echo ""
        echo "# 3. 手动处理相似文件"
        echo "# 打开此报告，逐对确认后手动删除或移动"
        echo '```'
        echo ""
        echo "---"
        echo ""
        echo "> ⚠️ **免责声明**: 相似度检测基于文件名和大小特征，可能存在误判。"
        echo "> 对于重要决策，请人工核实PDF内容后再操作。"

    } > "$SIMILARITY_REPORT"

    rm -f "$temp_files" "$temp_results"

    echo -e "  ${GREEN}✅ 报告已保存到: ${SIMILARITY_REPORT}${NC}"
    echo ""
}

# 智能去重 (结合多种策略)
smart_dedup() {
    echo ""
    echo -e "  ${RED}🤖 智能去重模式${NC}"
    echo ""
    echo -e "  将按以下优先级执行:"
    echo "  1. ${RED}完全重复${NC} (MD5相同) → 直接移动到回收站"
    echo "  2. ${YELLOW}高度相似${NC} (名称+大小相似) → 交互式确认"
    echo ""
    read -p "  是否继续? (y/N): " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { echo "  已取消"; return; }

    mkdir -p "$DEDUP_TRASH"

    local moved=0
    local kept=0
    local skipped=0
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="$DEDUP_TRASH/smart_dedup_${timestamp}.log"

    echo "# 智能去重日志 - $(date)" > "$log_file"
    echo "" >> "$log_file"

    # 收集文件
    local temp_files=$(mktemp)
    find "$BASE_DIR" -type f -name "*.pdf" \
        ! -path "*/.git/*" ! -path "*/.codegraph/*" \
        ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
        -printf "%s|%p\n" 2>/dev/null | sort -t'|' -k1 -n > "$temp_files"

    # 处理完全重复
    echo -e "  ${YELLOW}[1/2] 处理完全重复...${NC}"

    local prev_size="" prev_path=""
    while IFS='|' read -r size path; do
        [ -z "$size" ] && continue

        if [ -n "$prev_size" ] && [ "$size" = "$prev_size" ] && [ "$size" -gt 10000 ]; then
            # MD5验证
            local md5_prev=$(get_md5 "$prev_path")
            local md5_curr=$(get_md5 "$path")

            if [ -n "$md5_prev" ] && [ "$md5_prev" = "$md5_curr" ]; then
                # 决定保留哪个
                local rel_prev="${prev_path#$BASE_DIR/}"
                local rel_curr="${path#$BASE_DIR/}"
                local prev_depth=$(echo "$rel_prev" | tr -cd '/' | wc -c)
                local curr_depth=$(echo "$rel_curr" | tr -cd '/' | wc -c)

                local keep remove
                if [ "$prev_depth" -le "$curr_depth" ]; then
                    keep="$prev_path"; remove="$path"
                else
                    keep="$path"; remove="$prev_path"
                fi

                # 移动
                local dest="$DEDUP_TRASH/${timestamp}_$(basename "$remove")"
                mv "$remove" "$dest" 2>/dev/null

                if [ $? -eq 0 ]; then
                    moved=$((moved + 1))
                    echo "[AUTO-MOVED] ${remove#$BASE_DIR/}" >> "$log_file"
                    echo "[KEPT]      ${keep#$BASE_DIR/}" >> "$log_file"
                    echo "" >> "$log_file"
                fi
            fi
        fi

        prev_size="$size"
        prev_path="$path"
    done < "$temp_files"

    echo -e "  移动了 ${moved} 个完全重复文件"
    echo ""

    # 处理高度相似 (交互式确认)
    echo -e "  ${YELLOW}[2/2] 检查高度相似文件...${NC}"
    echo -e "  (跳过，可运行 --similarity-report 查看详细列表)"
    echo ""

    rm -f "$temp_files"

    echo -e "  ${GREEN}🎉 智能去重完成!${NC}"
    echo -e "  自动移动: ${moved} 个 (完全重复)"
    echo -e "  日志文件: ${log_file}"
    echo -e "  回收站:   ${DEDUP_TRASH}/"
    echo ""
    echo -e "  提示: 运行 ${CYAN}./paper_index.sh --similarity-report${NC} 查看需要人工确认的相似文件"

    # 刷新缓存
    rm -f "$CACHE_FILE"
}

# ============================================
# 论文自动分类功能
# ============================================

CLASSIFY_RULES="$BASE_DIR/.classify_rules.txt"
CLASSIFY_LOG="$BASE_DIR/.classify_log.csv"

# 加载分类规则
load_classify_rules() {
    if [ ! -f "$CLASSIFY_RULES" ]; then
        echo -e "  ${RED}❌ 分类规则文件不存在: ${CLASSIFY_RULES}${NC}"
        return 1
    fi
}

# 根据文件名分类论文 (高效版: 使用 awk 一次性处理)
classify_paper() {
    local filename="$1"
    local lower_name=$(echo "$filename" | tr '[:upper:]' '[:lower:]')

    # 使用 awk 高效匹配
    awk -F'|' -v name="$lower_name" '
    BEGIN {
        best_cat = ""
        best_pri = 999
        best_kw = ""
    }
    /^[^#]/ && $1 != "" {
        cat = $1
        keywords = $2
        priority = $3 + 0

        n = split(keywords, kw_arr, ",")
        for (i = 1; i <= n; i++) {
            kw = tolower(kw_arr[i])
            gsub(/^[ \t]+|[ \t]+$/, "", kw)
            if (kw == "") continue

            if (index(name, kw) > 0) {
                if (priority < best_pri) {
                    best_cat = cat
                    best_pri = priority
                    best_kw = kw
                } else if (priority == best_pri && best_cat != "") {
                    best_kw = best_kw ", " kw
                }
            }
        }
    }
    END {
        if (best_cat != "")
            print best_cat "|" best_pri "|" best_kw
        else
            print "others|99|no_match"
    }
    ' "$CLASSIFY_RULES"
}

# 预览分类建议 (高效版: 使用 awk 批量处理)
preview_classify() {
    echo ""
    echo -e "  ${CYAN}📋 论文自动分类预览${NC}"
    echo ""

    load_classify_rules || return

    # 使用 awk 一次性处理所有文件和规则 (高性能)
    local temp_results=$(mktemp)

    find "$BASE_DIR" -type f -name "*.pdf" \
        ! -path "*/.git/*" ! -path "*/.codegraph/*" \
        ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
        -printf "%p\n" 2>/dev/null | \
    awk -v base="$BASE_DIR/" '
    BEGIN {
        # 预加载规则
        while ((getline line < "'"$CLASSIFY_RULES"'") > 0) {
            if (line ~ /^#/ || line ~ /^[ \t]*$/) continue
            split(line, parts, "|")
            cat = parts[1]
            keywords = parts[2]
            pri = parts[3] + 0

            n = split(keywords, kw_arr, ",")
            for (i = 1; i <= n; i++) {
                kw = tolower(kw_arr[i])
                gsub(/^[ \t]+|[ \t]+$/, "", kw)
                if (kw == "") continue

                rule_count++
                rules[rule_count, "cat"] = cat
                rules[rule_count, "kw"] = kw
                rules[rule_count, "pri"] = pri
            }
        }
        close("'$"$CLASSIFY_RULES"'")
    }

    {
        filepath = $0
        sub(base, "", filepath)
        n = split(filepath, p, "/")
        current_cat = p[1]

        filename = filepath
        sub(/.*\//, "", filename)
        sub(/\.pdf$/i, "", filename)

        lower_name = tolower(filename)

        best_cat = ""
        best_pri = 999
        best_kw = ""

        for (r = 1; r <= rule_count; r++) {
            kw = rules[r, "kw"]
            if (index(lower_name, kw) > 0) {
                pri = rules[r, "pri"]
                if (pri < best_pri) {
                    best_cat = rules[r, "cat"]
                    best_pri = pri
                    best_kw = kw
                } else if (pri == best_pri && best_cat != "") {
                    best_kw = best_kw ", " kw
                }
            }
        }

        total++

        if (best_cat == "") best_cat = "others"

        if (best_cat != current_cat) {
            need_move++
            print filepath "|" best_cat "|" best_kw
        }
    }

    END {
        print "STATS:" total "|" need_move
    }
    ' > "$temp_results"

    # 解析结果
    local stats_line=$(grep "^STATS:" "$temp_results")
    local total=$(echo "$stats_line" | cut -d'|' -f2)
    local need_move=$(echo "$stats_line" | cut -d'|' -f3)

    echo -e "  ${YELLOW}扫描完成: ${total} 篇论文, ${need_move} 篇建议调整分类${NC}"
    echo ""

    if [ "$need_move" -gt 0 ]; then
        echo "  --------------------------------------------------------"

        # 按目标分类统计
        grep -v "^STATS:" "$temp_results" | cut -d'|' -f2 | sort | uniq -c | sort -rn | head -15 | \
        awk '{printf "  → %-25s %d 篇\n", $2, $1}'

        echo ""
        echo "  --------------------------------------------------------"
        echo -e "  ${CYAN}调整预览 (前50条):${NC}"
        echo ""

        grep -v "^STATS:" "$temp_results" | head -50 | while IFS='|' read -r current target kw; do
            local fname=$(basename "$current" .pdf)
            printf "  ${YELLOW}→${NC} %-55s ${GREEN}%s${NC}\n" "$fname" "[${target}]"
        done

        local remaining=$((need_move - 50))
        [ "$remaining" -gt 0 ] && echo -e "\n  ... 还有 ${remaining} 篇"
    else
        echo -e "  ${GREEN}✅ 所有论文已在正确的分类中!${NC}"
    fi

    rm -f "$temp_results"
    echo ""
}

# 详细分类报告
detail_classify() {
    echo ""
    echo -e "  ${CYAN}📝 生成详细分类报告...${NC}"

    load_classify_rules || return

    local report_file="$BASE_DIR/CLASSIFY_REPORT.md"
    local temp_all=$(mktemp)

    # 收集所有文件的分类信息
    {
        echo "# 论文自动分类报告"
        echo ""
        echo "> 自动生成于 **$(date '+%Y-%m-%d %H:%M')**"
        echo ""
        echo "---"
        echo ""
        echo "## 📊 分类概览"
        echo ""

        # 统计当前各分类数量
        echo "| 当前分类 | 论文数 |"
        echo "|----------|--------|"

        find "$BASE_DIR" -type f -name "*.pdf" \
            ! -path "*/.git/*" ! -path "*/.codegraph/*" \
            ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
            -printf "%h\n" 2>/dev/null | \
        sed "s|$BASE_DIR/||" | cut -d'/' -f1 | sort | uniq -c | sort -rn | \
        awk '{printf "| \`%s\` | %d |\n", $2, $1}'

        echo ""
        echo "---"
        echo ""
        echo "## 🔄 建议调整的论文"
        echo ""

        local move_count=0
        local skip_count=0

        find "$BASE_DIR" -type f -name "*.pdf" \
            ! -path "*/.git/*" ! -path "*/.codegraph/*" \
            ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
            -printf "%p\n" 2>/dev/null | while read -r filepath; do

            [ -z "$filepath" ] && continue

            local rel_path="${filepath#$BASE_DIR/}"
            local filename=$(basename "$filepath" .pdf)
            local current_cat=$(echo "$rel_path" | cut -d'/' -f1)

            local result=$(classify_paper "$filename")
            local suggest_cat=$(echo "$result" | cut -d'|' -f1)
            local keywords=$(echo "$result" | cut -d'|' -f3)

            if [ "$suggest_cat" != "$current_cat" ]; then
                move_count=$((move_count + 1))

                echo "### ${filename}"
                echo ""
                echo "| 属性 | 值 |"
                echo "|------|-----|"
                echo "| 当前位置 | \`${rel_path}\` |"
                echo "| 当前分类 | ${current_cat} |"
                echo "| **建议分类** | **${suggest_cat}** |"
                echo "| 匹配关键词 | ${keywords} |"
                echo "| 操作 | \`mv \"${rel_path}\" ${suggest_cat}/\` |"
                echo ""
            else
                skip_count=$((skip_count + 1))
            fi
        done

        echo "---"
        echo ""
        echo "## 📈 统计"
        echo ""
        echo "| 指标 | 数值 |"
        echo "|------|------|"
        echo "| 总论文数 | $(find "$BASE_DIR" -name "*.pdf" ! -path "*/.git/*" ! -path "*/.dedup_trash/*" | wc -l) |"
        echo "| 位置正确 | ${skip_count} |"
        echo "| 建议调整 | ${move_count} |"
        echo ""
        echo "---"
        echo ""
        echo "## ⚙️ 使用说明"
        echo ""
        echo '```bash'
        echo "# 预览分类建议"
        echo "./paper_index.sh --classify-preview"
        echo ""
        echo "# 自动执行分类"
        echo "./paper_index.sh --classify-auto"
        echo ""
        echo "# 编辑分类规则"
        echo "vim .classify_rules.txt"
        echo '```'

    } > "$report_file"

    rm -f "$temp_all"

    echo -e "  ${GREEN}✅ 报告已保存到: ${report_file}${NC}"
    echo ""
}

# 自动执行分类
auto_classify() {
    echo ""
    echo -e "  ${YELLOW}⚠️  自动分类模式${NC}"
    echo -e "  将根据规则文件 ${CLASSIFY_RULES} 移动论文"
    echo ""
    read -p "  是否继续? (y/N): " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { echo "  已取消"; return; }

    load_classify_rules || return

    local moved=0
    local skipped=0
    local failed=0
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="$BASE_DIR/.classify_${timestamp}.log"

    echo "# 分类操作日志 - $(date)" > "$log_file"
    echo "" >> "$log_file"

    # 创建所有目标目录
    while IFS='|' read -r cat _; do
        [[ "$cat" =~ ^#.*$ ]] && continue
        [[ -z "$cat" ]] && continue
        mkdir -p "$BASE_DIR/$cat" 2>/dev/null
    done < "$CLASSIFY_RULES"

    # 处理每个PDF文件
    find "$BASE_DIR" -type f -name "*.pdf" \
        ! -path "*/.git/*" ! -path "*/.codegraph/*" \
        ! -path "*/.dedup_trash/*" ! -path "*/PPTS/*" ! -path "*/CS224N_slides/*" \
        -printf "%p\n" 2>/dev/null | while read -r filepath; do

        [ -z "$filepath" ] && continue

        local rel_path="${filepath#$BASE_DIR/}"
        local filename=$(basename "$filepath" .pdf)
        local current_cat=$(echo "$rel_path" | cut -d'/' -f1)

        # 获取建议分类
        local result=$(classify_paper "$filename")
        local suggest_cat=$(echo "$result" | cut -d'|' -f1)
        local keywords=$(echo "$result" | cut -d'|' -f3)

        # 如果需要移动
        if [ "$suggest_cat" != "$current_cat" ]; then
            local dest_dir="$BASE_DIR/$suggest_cat"
            local dest_file="$dest_dir/$(basename "$filepath")"

            # 处理目标位置已存在同名文件的情况
            if [ -f "$dest_file" ]; then
                # 添加数字后缀
                local counter=1
                while [ -f "${dest_file%.pdf}_${counter}.pdf" ]; do
                    counter=$((counter + 1))
                done
                dest_file="${dest_file%.pdf}_${counter}.pdf"
            fi

            # 执行移动
            mv "$filepath" "$dest_file" 2>/dev/null

            if [ $? -eq 0 ]; then
                moved=$((moved + 1))
                echo "[MOVED] ${rel_path} -> ${suggest_cat}/ (${keywords})" >> "$log_file"
                echo -e "  ${GREEN}✓${NC} ${filename:0:60}"
                echo -e "     ${current_cat} → ${suggest_cat}"
            else
                failed=$((failed + 1))
                echo "[FAILED] ${rel_path}" >> "$log_file"
            fi
        else
            skipped=$((skipped + 1))
        fi
    done

    echo ""
    echo -e "  ${GREEN}🎉 分类整理完成!${NC}"
    echo -e "  移动文件: ${moved} 个"
    echo -e "  跳过文件: ${skipped} 个 (已正确分类)"
    echo -e "  失败文件: ${failed} 个"
    echo -e "  日志文件: ${log_file}"
    echo ""

    # 刷新缓存
    rm -f "$CACHE_FILE"
}

# 分析特定论文的分类
analyze_single() {
    local query="$1"

    load_classify_rules || return

    echo ""
    echo -e "  ${CYAN}🔍 分析论文分类: ${query}${NC}"
    echo ""

    local result=$(classify_paper "$query")
    local suggest_cat=$(echo "$result" | cut -d'|' -f1)
    local priority=$(echo "$result" | cut -d'|' -f2)
    local keywords=$(echo "$result" | cut -d'|' -f3)

    echo -e "  论文标题: ${YELLOW}${query}${NC}"
    echo -e "  建议分类: ${GREEN}${suggest_cat}${NC} (优先级: ${priority})"
    echo -e "  匹配关键词: ${keywords}"
    echo ""
}

# 显示分类规则统计
show_rules_stats() {
    echo ""
    echo -e "  ${CYAN}📖 分类规则统计${NC}"
    echo ""

    if [ ! -f "$CLASSIFY_RULES" ]; then
        echo -e "  ${RED}❌ 规则文件不存在${NC}"
        return
    fi

    local rules_total=$(grep -c '|' "$CLASSIFY_RULES" 2>/dev/null || echo 0)
    local categories=$(cut -d'|' -f1 "$CLASSIFY_RULES" | grep -v '^#' | grep -v '^$' | sort -u | wc -l)
    local total_keywords=$(cut -d'|' -f2 "$CLASSIFY_RULES" | tr ',' '\n' | grep -v '^$' | wc -l)

    echo "  规则总数: ${rules_total}"
    echo "  覆盖分类: ${categories} 个"
    echo "  关键词数: ${total_keywords} 个"
    echo ""
    echo "  各分类关键词覆盖:"
    echo "  --------------------------------------------------------"

    while IFS='|' read -r cat keywords _; do
        [[ "$cat" =~ ^#.*$ ]] && continue
        [[ -z "$cat" ]] && continue

        local count=$(echo "$keywords" | tr ',' '\n' | grep -v '^$' | wc -l)
        printf "  %-25s %d 个关键词\n" "$cat" "$count"
    done < "$CLASSIFY_RULES" | sort -t'(' -k2 -rn

    echo ""
}

# ============================================
# 主程序
# ============================================
main() {
    local action="index"
    local output_file=""
    local search_query=""
    local category_name=""
    local no_cache=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)   output_file="$2"; shift 2 ;;
            --stats)       action="stats"; shift ;;
            --search)      action="search"; search_query="$2"; shift 2 ;;
            --category)    action="category"; category_name="$2"; shift 2 ;;
            --refresh)     no_cache=true; shift ;;
            --dedup)       action="dedup"; shift ;;
            --dedup-report) action="dedup_report"; shift ;;
            --dedup-auto)  action="dedup_auto"; shift ;;
            --restore)     action="restore"; shift ;;
            --detect-similar|--similarity) action="detect_similar"; shift ;;
            --similarity-report)       action="similarity_report"; shift ;;
            --smart-dedup)             action="smart_dedup"; shift ;;
            --classify-preview)   action="classify_preview"; shift ;;
            --classify-detail)    action="classify_detail"; shift ;;
            --classify-auto)      action="classify_auto"; shift ;;
            --classify-analyze)   action="classify_analyze"; search_query="$2"; shift 2 ;;
            --classify-rules)     action="classify_rules"; shift ;;
            -h|--help)
                echo "DecryptPrompt 论文分类索引工具"
                echo ""
                echo "用法: $0 [选项]"
                echo ""
                echo "索引功能:"
                echo "  (无参数)              生成 Markdown 索引"
                echo "  -o, --output FILE     保存输出到文件"
                echo "  --stats               显示统计信息"
                echo "  --search KEYWORD      搜索论文"
                echo "  --category NAME       显示指定分类"
                echo "  --refresh             强制刷新缓存"
                echo ""
                echo "去重功能:"
                echo "  --dedup               检测重复论文 (MD5)"
                echo "  --dedup-report        生成详细去重报告 (DEDUP_REPORT.md)"
                echo "  --dedup-auto          自动去重 (移动到 .dedup_trash/)"
                echo "  --restore             查看回收站并恢复文件"
                echo ""
                echo "相似度检测 (高级):"
                echo "  --detect-similar      深度相似度分析 (名称+大小+Jaccard)"
                echo "  --similarity-report   生成相似度报告 (SIMILARITY_REPORT.md)"
                echo "  --smart-dedup         智能去重 (自动+交互式确认)"
                echo ""
                echo "自动分类功能:"
                echo "  --classify-preview     预览分类建议 (不移动文件)"
                echo "  --classify-detail      生成详细分类报告 (CLASSIFY_REPORT.md)"
                echo "  --classify-auto        自动执行分类整理"
                echo "  --classify-analyze TITLE 分析单篇论文的分类"
                echo "  --classify-rules       显示分类规则统计"
                echo ""
                echo "配置文件:"
                echo "  .classify_rules.txt    分类规则 (可编辑自定义)"
                echo ""
                echo "  -h, --help            显示帮助"
                exit 0 ;;
            *) shift ;;
        esac
    done

    # 刷新缓存时删除旧缓存
    [ "$no_cache" = true ] && rm -f "$CACHE_FILE"

    # 更新/加载缓存 (分类和相似度操作不需要索引缓存)
    if [[ ! "$action" =~ classify_* ]] && [[ ! "$action" =~ similarity* ]] && \
       [[ ! "$action" == detect_simular ]] && [[ ! "$action" == smart_dedup ]]; then
        update_cache
    fi

    # 执行操作
    case $action in
        stats)              show_stats ;;
        search)             search_papers "$search_query" ;;
        category)        show_category "$category_name" ;;
        index)           generate_markdown "$output_file" ;;
        dedup)           detect_duplicates ;;
        dedup_report)    generate_dedup_report ;;
        dedup_auto)      auto_dedup ;;
        restore)         restore_from_trash ;;
        detect_similar)  detect_similar_papers ;;
        similarity_report) generate_similarity_report ;;
        smart_dedup)     smart_dedup ;;
        classify_preview) preview_classify ;;
        classify_detail)  detail_classify ;;
        classify_auto)    auto_classify ;;
        classify_analyze) analyze_single "$search_query" ;;
        classify_rules)   show_rules_stats ;;
    esac
}

main "$@"
