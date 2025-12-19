#!/bin/bash
set -eo pipefail

# 初始化变量
indir=""
outdir=""
datatype=""
db_path=""  # 数据库路径
threads_per_task=4
parallel_tasks=8
overwrite=0

# 帮助信息
usage() {
    echo "Usage: $0 [options]"
    echo "支持指定数据库路径的并行化eggNOG批量注释脚本"
    echo "必需选项:"
    echo "  --indir          输入文件目录（包含所有待注释的序列文件）i"
    echo "  --outdir         输出结果目录"
    echo "  --type           输入数据类型 (protein: 蛋白质序列; cds: 编码序列)"
    echo "可选选项:"
    echo "  --db             eggNOG数据库路径（若不指定则使用默认配置）"
    echo "  --threads-per    每个注释任务使用的CPU线程数 (默认: 4)"
    echo "  --parallel       并行运行的任务数量 (默认: 8)"
    echo "  --overwrite      覆盖已存在的输出文件 (默认: 不覆盖)"
    echo "  --help           显示帮助信息"
    exit 1
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --indir)
            indir="$2"
            shift 2
            ;;
        --outdir)
            outdir="$2"
            shift 2
            ;;
        --type)
            datatype="$2"
            shift 2
            ;;
        --db)
            db_path="$2"
            shift 2
            ;;
        --threads-per)
            threads_per_task="$2"
            shift 2
            ;;
        --parallel)
            parallel_tasks="$2"
            shift 2
            ;;
        --overwrite)
            overwrite=1
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "错误: 未知选项 $1" >&2
            usage
            ;;
    esac
done

# 检查必需参数
if [[ -z "$indir" || -z "$outdir" || -z "$datatype" ]]; then
    echo "错误: 缺少必需参数！" >&2
    usage
fi

# 检查依赖工具
if ! command -v emapper.py &> /dev/null; then
    echo "错误: 未找到emapper.py，请先安装eggNOG-mapper" >&2
    exit 1
fi

if ! command -v parallel &> /dev/null; then
    echo "错误: 未找到parallel，请先安装GNU Parallel" >&2
    exit 1
fi

# 检查输入目录
if [[ ! -d "$indir" ]]; then
    echo "错误: 输入目录 $indir 不存在！" >&2
    exit 1
fi

# 检查数据库路径（若指定）
if [[ -n "$db_path" ]]; then
    if [[ ! -d "$db_path" ]]; then
        echo "错误: 指定的数据库路径 $db_path 不存在或不是目录！" >&2
        exit 1
    fi
    # 检查数据库关键文件（根据eggNOG数据库结构）
    required_db_files=("eggnog.db")
    missing_files=()
    for file in "${required_db_files[@]}"; do
        if [[ ! -f "$db_path/$file" && ! -f "$db_path/data/$file" ]]; then
            missing_files+=("$file")
        fi
    done
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo "错误: 数据库路径中缺少关键文件: ${missing_files[*]}" >&2
        exit 1
    fi
fi

# 创建输出目录
mkdir -p "$outdir" || { echo "错误: 无法创建输出目录 $outdir" >&2; exit 1; }

# 验证线程数和并行任务数
if ! [[ "$threads_per_task" =~ ^[1-9][0-9]*$ ]]; then
    echo "错误: 每个任务的线程数必须是正整数！" >&2
    exit 1
fi

if ! [[ "$parallel_tasks" =~ ^[1-9][0-9]*$ ]]; then
    echo "错误: 并行任务数量必须是正整数！" >&2
    exit 1
fi

# 验证数据类型
if [[ "$datatype" != "proteins" && "$datatype" != "CDS" && "$datatype" != "genome" && "$datatype" != "metagenome" ]]; then
    echo "错误: 数据类型必须是 'proteins'或'CDS'或'genome'或'metagenome'！" >&2
    exit 1
fi

# 收集输入文件
input_files=("$indir"/*)
valid_files=()
for file in "${input_files[@]}"; do
    if [[ -f "$file" ]]; then
        valid_files+=("$file")
    fi
done

file_count=${#valid_files[@]}
if [[ $file_count -eq 0 ]]; then
    echo "错误: 输入目录 $indir 中未找到任何文件！" >&2
    exit 1
fi

# 显示运行参数
echo "======================================"
echo "开始并行eggNOG批量注释"
echo "输入目录: $indir"
echo "输出目录: $outdir"
echo "数据类型: $datatype"
echo "数据库路径: ${db_path:-默认配置}"
echo "每个任务线程数: $threads_per_task"
echo "并行任务数量: $parallel_tasks"
echo "总任务数: $file_count"
echo "总线程需求: $((threads_per_task * parallel_tasks))"
echo "覆盖模式: $(if [[ $overwrite -eq 1 ]]; then echo "开启"; else echo "关闭"; fi)"
echo "======================================"

# 定义处理单个文件的函数
process_file() {
    local input_file="$1"
    local outdir="$2"
    local datatype="$3"
    local threads="$4"
    local overwrite="$5"
    local db_path="$6"
    
    local filename=$(basename "$input_file")
    local base_name="${filename%.*}"
    local output_prefix="$outdir/$base_name"
    local log_file="$outdir/${base_name}.log"

    case "$datatype" in
        "cds"|"CDS"|"Cds")
            datatype="CDS"
            ;;
        "protein"|"proteins"|"Prot"|"prot")
            datatype="proteins"
            ;;
        "genome"|"Genome")
            datatype="genome"
            ;;
        "metagenome"|"Metagenome")
            datatype="metagenome"
            ;;
    esac
    
    # 检查输出是否已存在
    if [[ -f "${output_prefix}.emapper.annotations" && $overwrite -eq 0 ]]; then
        echo "跳过: $filename (已存在)"
        return 0
    fi
    
    echo "开始处理: $filename"
    # 构建emapper命令（包含数据库路径参数）
    emapper_cmd="emapper.py \
        -i "$input_file" \
        --output "$output_prefix" \
        --cpu "$threads" \
        --itype "$datatype" \
        $([[ $overwrite -eq 1 ]] && echo "--override") \
        $([[ -n "$db_path" ]] && echo "--data_dir $db_path")"
    
    # 执行命令并记录日志
    eval $emapper_cmd > "$log_file" 2>&1
    
    # 检查运行结果
    if [[ $? -eq 0 ]]; then
        echo "完成: $filename"
        return 0
    else
        echo "失败: $filename (日志: $log_file)"
        return 1
    fi
}

# 导出函数以便parallel使用
export -f process_file

# 使用parallel并行并行处理文件（传递数据库路径参数）
printf "%s\n" "${valid_files[@]}" | parallel \
    --jobs "$parallel_tasks" \
    --delay 0.5 \
    --bar \
    process_file {} "$outdir" "$datatype" "$threads_per_task" "$overwrite" "$db_path"

# 统计结果
echo "======================================"
echo "并行处理完成"
echo "总文件数: $file_count"

success_count=$(find "$outdir" -maxdepth 1 -name "*.emapper.annotations" | wc -l)
failed_count=$((file_count - success_count))

echo "成功处理: $success_count"
echo "处理失败: $failed_count"
echo "结果目录: $outdir"
if [[ $failed_count -gt 0 ]]; then
    echo "失败任务日志: $outdir/*.log"
fi
echo "======================================"

exit 0
