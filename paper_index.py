#!/usr/bin/env python3
"""
DecryptPrompt 论文分类索引工具

用法:
    python paper_index.py                    # 生成完整索引 (Markdown)
    python paper_index.py --format json       # 输出 JSON 格式
    python paper_index.py --search "RLHF"     # 搜索包含关键词的论文
    python paper_index.py --stats             # 仅输出统计信息
    python paper_index.py --category RLHF     # 查看特定分类的论文列表
"""

import os
import sys
import json
import argparse
from pathlib import Path
from collections import defaultdict
from datetime import datetime


# 项目根目录
BASE_DIR = Path(__file__).parent.resolve()

# 排除的目录
EXCLUDE_DIRS = {".git", ".codegraph", "PPTS", "CS224N_slides"}

# 分类中文描述映射
CATEGORY_DESCRIPTIONS = {
    "LLMS": "主流大语言模型",
    "new_model": "新型模型架构",
    "MOE": "混合专家模型",
    "domain_llms": "领域专用模型",
    "pretrain_data": "预训练数据与方法",
    "post_train": "后训练：推理扩展、慢思维、RL智能体",
    "instruction_tunning": "指令微调",
    "prompt_tunning": "Prompt微调技术",
    "RLHF": "人类反馈强化学习",
    "prompt_engineer": "Prompt工程技术",
    "prompt_chain_of_thought": "思维链推理",
    "LLM_agent": "LLM智能体",
    "LLM_memory": "智能体记忆系统",
    "LLM_dialog": "对话系统",
    "LLM_chart": "图表理解",
    "LLM_ability": "LLM能力分析",
    "RAG": "检索增强生成",
    "LLM_KG": "知识图谱+LLM",
    "multimodal": "多模态模型",
    "image_generation": "图像生成",
    "inference": "推理优化",
    "Quantization": "模型量化",
    "reliablity": "可靠性：幻觉检测、对抗鲁棒性",
    "self-evolution": "自进化LLM",
    "adversarial": "对抗攻防",
    "nl2sql": "自然语言转SQL",
    "code_generation": "代码生成",
    "timeseries": "时间序列预测",
    "context_engineer": "上下文工程",
    "evaluation": "评估基准与综述",
    "survey": "综述论文",
    "model_edit": "模型编辑",
    "model_merge": "模型合并",
    "long_input": "长上下文处理",
    "long_output": "长输出生成",
    "multi-turn": "多轮对话",
    "train_withcode": "代码数据训练",
    "humanoid": "人形/AI对齐",
    "others": "其他",
}


def scan_papers(base_dir: Path) -> dict:
    """
    扫描所有目录中的PDF文件，返回分类索引
    返回结构: {category: {subcategory: [file_info, ...]}}
    """
    index = defaultdict(lambda: defaultdict(list))
    total = 0

    for category_dir in sorted(base_dir.iterdir()):
        if not category_dir.is_dir() or category_dir.name in EXCLUDE_DIRS:
            continue

        category = category_dir.name

        # 扫描该分类下的所有PDF（包括子目录）
        for pdf_path in sorted(category_dir.rglob("*.pdf")):
            # 确定子分类（相对于分类目录的路径）
            rel_path = pdf_path.relative_to(category_dir)
            if len(rel_path.parts) > 1:
                subcategory = rel_path.parts[0]
            else:
                subcategory = "_root"  # 根级文件

            file_info = {
                "name": pdf_path.stem,
                "path": str(pdf_path.relative_to(base_dir)),
                "size_kb": round(pdf_path.stat().st_size / 1024, 1),
                "modified": datetime.fromtimestamp(
                    pdf_path.stat().st_mtime
                ).strftime("%Y-%m-%d"),
            }

            index[category][subcategory].append(file_info)
            total += 1

    return dict(index), total


def generate_markdown(index: dict, total: int, output_file: Path | None = None) -> str:
    """生成 Markdown 格式的索引"""
    lines = []
    lines.append("# DecryptPrompt 论文索引")
    lines.append("")
    lines.append(f"> 自动生成于 {datetime.now().strftime('%Y-%m-%d %H:%M')} | 共 **{total}** 篇论文")
    lines.append("")

    # 统计概览
    lines.append("## 📊 分类统计")
    lines.append("")
    lines.append("| 分类 | 描述 | 论文数 |")
    lines.append("|------|------|--------|")

    category_counts = {
        cat: sum(len(files) for sub in subs.values() for files in [subs[sub]])
        for cat, subs in index.items()
    }

    for category, count in sorted(category_counts.items(), key=lambda x: -x[1]):
        desc = CATEGORY_DESCRIPTIONS.get(category, "")
        lines.append(f"| `{category}` | {desc} | {count} |")

    lines.append("")
    lines.append("---")
    lines.append("")

    # 详细索引
    lines.append("## 📁 详细索引")
    lines.append("")

    for category in sorted(index.keys()):
        subcategories = index[category]
        cat_total = sum(len(files) for files in subcategories.values())
        desc = CATEGORY_DESCRIPTIONS.get(category, "")

        lines.append(f"### {category}")
        if desc:
            lines.append(f"*{desc}* ({cat_total} 篇)")
        lines.append("")

        for subcat in sorted(subcategories.keys()):
            files = subcategories[subcat]

            if subcat == "_root":
                lines.append("**根目录**")
            else:
                lines.append(f"**{subcat}** ({len(files)} 篇)")

            lines.append("")
            for f in files:
                lines.append(
                    f"- [{f['name']}]({f['path']}) "
                    f"({f['size_kb']} KB, {f['modified']})"
                )
            lines.append("")

        lines.append("---")
        lines.append("")

    content = "\n".join(lines)

    if output_file:
        output_file.write_text(content, encoding="utf-8")
        print(f"✅ 索引已保存到: {output_file}")

    return content


def generate_json(index: dict, total: int, output_file: Path | None = None) -> str:
    """生成 JSON 格式的索引"""
    output = {
        "generated_at": datetime.now().isoformat(),
        "total_papers": total,
        "categories": {},
    }

    for category, subcategories in index.items():
        output["categories"][category] = {
            "description": CATEGORY_DESCRIPTIONS.get(category, ""),
            "total": sum(len(files) for files in subcategories.values()),
            "subcategories": {
                subcat: [
                    {
                        "name": f["name"],
                        "path": f["path"],
                        "size_kb": f["size_kb"],
                        "modified": f["modified"],
                    }
                    for f in files
                ]
                for subcat, files in subcategories.items()
            },
        }

    content = json.dumps(output, ensure_ascii=False, indent=2)

    if output_file:
        output_file.write_text(content, encoding="utf-8")
        print(f"✅ JSON索引已保存到: {output_file}")

    return content


def print_stats(index: dict, total: int):
    """打印统计信息"""
    print("\n" + "=" * 60)
    print("📊 DecryptPrompt 论文库统计")
    print("=" * 60)
    print(f"\n总论文数: {total}")
    print(f"总分类数: {len(index)}")
    print()

    # Top 10 分类
    counts = [
        (cat, sum(len(files) for files in subs.values()))
        for cat, subs in index.items()
    ]
    counts.sort(key=lambda x: -x[1])

    print("📈 论文数量 TOP 10 分类:")
    print("-" * 40)
    for i, (cat, count) in enumerate(counts[:10], 1):
        desc = CATEGORY_DESCRIPTIONS.get(cat, "")[:20]
        bar = "█" * min(count // 5, 30)
        print(f"  {i:2}. {cat:<25} {count:>4} {bar}")

    print()
    print("📂 所有分类:")
    print("-" * 40)
    for cat, count in counts:
        print(f"  {cat:<30} {count:>4} 篇")


def search_papers(index: dict, query: str):
    """搜索论文"""
    query_lower = query.lower()
    results = []

    for category, subcategories in index.items():
        for subcat, files in subcategories.items():
            for f in files:
                if query_lower in f["name"].lower() or query_lower in category.lower():
                    results.append(
                        {
                            "category": category,
                            "subcategory": subcat,
                            **f,
                        }
                    )

    print(f"\n🔍 搜索 '{query}' 找到 {len(results)} 个结果:\n")

    for r in results:
        subcat_display = "" if r["subcategory"] == "_root" else f"/{r['subcategory']}"
        print(f"  [{r['category']}{subcat_display}] {r['name']}")
        print(f"    路径: {r['path']} | {r['size_kb']} KB")
        print()


def show_category(index: dict, category: str):
    """显示特定分类的论文列表"""
    if category not in index:
        print(f"❌ 未找到分类: {category}")
        print(f"\n可用分类: {', '.join(sorted(index.keys()))}")
        return

    subcategories = index[category]
    desc = CATEGORY_DESCRIPTIONS.get(category, "")
    total = sum(len(files) for files in subcategories.values())

    print(f"\n📁 分类: {category}")
    if desc:
        print(f"   描述: {desc}")
    print(f"   论文数: {total}")
    print("-" * 50)

    for subcat in sorted(subcategories.keys()):
        files = subcategories[subcat]
        display_name = "根目录" if subcat == "_root" else subcat
        print(f"\n  [{display_name}] ({len(files)} 篇)")

        for f in files:
            print(f"    • {f['name']}")
            print(f"      {f['size_kb']} KB | {f['modified']}")


def main():
    parser = argparse.ArgumentParser(
        description="DecryptPrompt 论文分类索引工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python paper_index.py                     # 生成 Markdown 索引到 stdout
  python paper_index.py -o index.md         # 保存索引到文件
  python paper_index.py --format json       # 输出 JSON 格式
  python paper_index.py --stats             # 显示统计信息
  python paper_index.py --search "attention" # 搜索论文
  python paper_index.py --category RLHF     # 查看 RLHF 分类
        """,
    )

    parser.add_argument(
        "-o", "--output", type=str, help="输出文件路径 (如 index.md 或 index.json)"
    )
    parser.add_argument(
        "--format", choices=["markdown", "json"], default="markdown", help="输出格式"
    )
    parser.add_argument("--stats", action="store_true", help="仅显示统计信息")
    parser.add_argument("--search", type=str, help="搜索关键词")
    parser.add_argument("--category", type=str, help="查看指定分类")

    args = parser.parse_args()

    # 扫描论文
    print("🔍 扫描论文库...")
    index, total = scan_papers(BASE_DIR)
    print(f"✅ 完成! 共找到 {total} 篇论文\n")

    # 执行操作
    if args.stats:
        print_stats(index, total)
    elif args.search:
        search_papers(index, args.search)
    elif args.category:
        show_category(index, args.category)
    else:
        output_path = Path(args.output) if args.output else None

        if args.format == "json":
            generate_json(index, total, output_path)
            if not output_path:
                print(generate_json(index, total))
        else:
            content = generate_markdown(index, total, output_path)
            if not output_path:
                print(content)


if __name__ == "__main__":
    main()
