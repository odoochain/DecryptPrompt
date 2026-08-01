# CODEBUDDY.md

This file provides guidance to CodeBuddy Code when working with code in this repository.

## Project Overview

**DecryptPrompt** is a knowledge repository focused on Large Language Model (LLM) research, not a software project. It collects academic papers, blog posts, tutorials, and resource lists organized by topic. Content is primarily in Chinese.

## Repository Structure

```
├── README.md                  # Main index: paper lists, blog series, external resource links
├── 开源模型.MD                 # Open-source model rankings and benchmarks
├── 开源框架.MD                 # Open-source frameworks (inference, fine-tuning, Agent, RAG, Prompt)
├── 开源数据.MD                 # Open-source datasets (SFT, RLHF, Pretrain)
├── AIGC各领域应用.MD/.MD2      # AIGC applications across domains
├── 教程博客会议.MD             # Prompt tutorials, classic blogs, conference interviews
│
├── LLMS/                      # Mainstream LLM papers (GPT-4, LLaMA, Qwen, DeepSeek, etc.)
├── new_model/                 # Novel model architectures (MoE, diffusion LM, etc.)
├── MOE/                       # Mixture of Experts
├── domain_llms/               # Domain-specific LLMs
│
├── pretrain_data/             # Pre-training data & methods
├── post_train/                # Post-training: inference scaling, slow-thinking CoT, RL agents
├── instruction_tunning/       # Instruction tuning (includes Ability Loss subfolder)
├── prompt_tunning/            # Prompt tuning (Prefix-tuning, P-tuning, etc.)
├── RLHF/                      # RLHF methods (PPO, DPO, RLAIF, Constitutional AI)
│
├── prompt_engineer/           # Prompt engineering techniques
├── prompt_chain_of_thought/   # Chain-of-Thought reasoning (zero-shot, few-shot, ToT, GoT, etc.)
│
├── LLM_agent/                 # LLM Agents (ReAct, Toolformer, multi-agent systems)
├── LLM_memory/                # Agent memory systems
├── LLM_dialog/                # Dialogue systems
├── LLM_chart/                 # Chart/table understanding
├── LLM_ability/               # LLM capability analysis
│
├── RAG/                       # Retrieval-Augmented Generation
├── LLM_KG/                    # Knowledge Graph + LLM
│
├── multimodal/                # Multimodal models
├── image_generation/          # Image generation (diffusion, VQ-VAE)
│
├── inference/                 # Inference optimization
├── Quantization/              # Model quantization
│
├── reliablity/                # Reliability: hallucination detection, adversarial robustness
├── self-evolution/            # Self-improving LLMs
├── adversarial/               # Adversarial attacks/defenses
│
├── nl2sql/                    # Natural language to SQL
├── code_generation/           # Code generation
├── timeseries/                # Time series forecasting
├── context_engineer/          # Context engineering for agents
│
├── evaluation/                # LLM evaluation benchmarks & surveys
├── survey/                    # Survey papers
├── model_edit/                # Model editing techniques
├── model_merge/               # Model merging
│
├── long_input/                # Long context handling
├── long_output/               # Long output generation
├── multi-turn/                # Multi-turn dialogue
│
├── train_withcode/            # Training with code data
├── humanoid/                  # Humanoid/AI alignment
│
├── PPTS/                      # Presentation slides (.pptx) with index at ppt_link.md
├── CS224N_slides/             # CS224N NLP course slides
│
└── others/                    # Miscellaneous papers
```

## Key Conventions

### Paper Organization
- Papers are stored as PDFs in topic-specific directories
- Some directories contain subdirectories for sub-topics (e.g., `instruction_tunning/Ability Loss/`)
- The `:star:` marker in README.md indicates highly recommended/pivotal papers

### Blog Series ("解密Prompt" Series)
- 68+ blog posts hosted on Tencent Cloud Developer, indexed in README.md
- Each post covers 1-3 related papers with code examples and analysis
- Series progresses from basic prompt tuning → instruction tuning → RLHF → CoT → Agent → RAG → advanced reasoning

### Resource Documents (Chinese)
- **开源模型.MD**: Model leaderboards and selection guides
- **开源框架.MD**: Framework comparisons (training, inference, agent, RAG)
- **开源数据.MD**: Dataset catalogs by task type
- **教程博客会议.MD**: Learning resources and conference coverage

## Working with This Repository

### Paper Index Tool (`paper_index.sh`)

A Bash script for indexing, searching, deduplicating, similarity detection, and auto-classifying the paper collection.

```bash
# Index & Search
./paper_index.sh                     # Generate Markdown index (stdout)
./paper_index.sh -o PAPER_INDEX.md   # Save index to file
./paper_index.sh --stats             # Show statistics (1183 papers, 40 categories)
./paper_index.sh --search "RLHF"     # Search by keyword
./paper_index.sh --category RLHF     # List specific category

# Deduplication (detects 37 duplicate groups via MD5)
./paper_index.sh --dedup             # Detect duplicates (size + MD5 verification)
./paper_index.sh --dedup-report      # Generate DEDUP_REPORT.md with recommendations
./paper_index.sh --dedup-auto        # Auto-clean: move dupes to .dedup_trash/ (safe mode)
./paper_index.sh --restore           # View/restore from trash

# Similarity Detection (advanced: filename + size + Jaccard)
./paper_index.sh --detect-similar    # Deep similarity analysis
./paper_index.sh --similarity-report # Generate SIMILARITY_REPORT.md
./paper_index.sh --smart-dedup       # Smart dedup (auto + interactive)

# Auto-Classification (keyword-based, 384 rules across 39 categories)
./paper_index.sh --classify-preview  # Preview classification suggestions
./paper_index.sh --classify-detail   # Generate CLASSIFY_REPORT.md with full details
./paper_index.sh --classify-auto      # Execute auto-classification (moves files)
./paper_index.sh --classify-analyze "Paper Title"  # Analyze single paper
./paper_index.sh --classify-rules    # Show rule statistics

# Cache Management
./paper_index.sh --refresh           # Force rebuild cache
```

**Deduplication Strategy**:
1. **Size-based pre-filtering**: Groups files with identical byte sizes
2. **MD5 confirmation**: Uses PowerShell `Get-FileHash` for content verification
3. **Smart retention**: Keeps file in shallower directory path (more canonical location)
4. **Safe deletion**: Moves to `.dedup_trash/` with timestamped logs (recoverable)

**Similarity Detection Algorithm**:
- **Filename normalization**: Lowercase, remove punctuation/special chars
- **Jaccard similarity**: Word-level set intersection over union (threshold: ≥70%)
- **Size ratio comparison**: File size similarity (threshold: ≥95%)
- **Multi-category scan**: Compares papers across all directories (not just same folder)
- **Output tiers**: 🔴 Exact duplicates (MD5 match) | 🟡 High similarity (name+size)

**Auto-Classification System**:
- **Rule file**: `.classify_rules.txt` — 40 categories, 384 keywords, priority-based matching
- **Matching logic**: Case-insensitive substring match on paper filename; lowest priority wins
- **Safety**: Preview mode shows changes before execution; logs all moves for audit
- **Customization**: Edit `.classify_rules.txt` to add/modify keywords per category

**Cache files**: `.paper_cache.txt` (index), `.md5_cache.txt` (hashes), auto-expire after 1 hour

### Adding New Papers
1. Place PDF in the most relevant topic directory
2. Add entry to README.md under the appropriate section
3. Consider if it deserves a `:star:` marker for high importance

### Adding New Resources
- Framework/model/dataset links go into the corresponding `.MD` resource file
- Blog or tutorial links go into `教程博客会议.MD`

### Navigation Tips
- Start with README.md for an overview of all content
- Use topic directories to dive deep into specific areas
- The "解密Prompt" blog series provides progressive learning paths from basics to advanced topics
- Resource `.MD` files are better for finding practical tools/frameworks than academic papers
