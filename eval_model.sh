#!/bin/bash

set -e
# 解析命令行参数
if [ -n "$1" ]; then
    model="$1"
else
    model="qwen3:4b"
fi
# 定义日志文件
model_safe=$(echo "$model" | sed 's/[^a-zA-Z0-9]/_/g')
# 获取当前时间
log_time=$(date '+%Y%m%d_%H%M%S')
log_file="eval_${model_safe}_${log_time}.log"
# 清空日志文件
> "$log_file"

# 记录开始时间
start_time=$(date +%s.%N)
start_time_human=$(date '+%Y-%m-%d %H:%M:%S')
echo "开始执行，当前时间: $start_time_human（时间戳: $start_time）" | tee -a "$log_file"

# 检查 curl 是否可用
if ! command -v curl &> /dev/null; then
    echo "错误: curl 未安装，请先安装 curl" | tee -a "$log_file"
    exit 1
fi


# 将 model 名中的特殊字符替换为下划线
model_safe=$(echo "$model" | sed 's/[^a-zA-Z0-9]/_/g')
prompt="写一首七言律诗，描写夏日荷塘的， 要求不要出现'夏日'，用markdown给出结果，并给出诗名"

echo "准备发送请求到 http://localhost:11434/api/generate ..." | tee -a "$log_file"
echo "使用的模型: $model" | tee -a "$log_file"
echo "使用的 prompt: $prompt" | tee -a "$log_file"

# 执行请求并捕获输出和 HTTP 状态码
echo "curl 开始" | tee -a "$log_file"
response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$model\",
    \"prompt\": \"$prompt\",
    \"stream\": false
  }" 2>&1)



echo "curl 结束" | tee -a "$log_file"
echo "原始 response: $response" | tee -a "$log_file"

# 分离响应体和状态码
body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')
status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

# 记录结束时间并计算耗时
end_time=$(date +%s.%N)
end_time_human=$(date '+%Y-%m-%d %H:%M:%S')
echo "请求结束，当前时间: $end_time_human（时间戳: $end_time）" | tee -a "$log_file"

# 计算耗时
duration=$(LC_ALL=C echo "$end_time - $start_time" | bc)

# 检查 HTTP 状态码
if [ "$status" -ne 200 ]; then
    echo "❌ 请求失败，HTTP 状态码: $status" | tee -a "$log_file"
    echo "响应内容:" | tee -a "$log_file"
    echo "$body" | tee -a "$log_file"
    exit 2
fi

# 格式化输出
echo "═════════ 响应结果 ═════════" | tee -a "$log_file"
echo "$body" | tee -a "$log_file"
echo "═════════ 执行统计 ═════════" | tee -a "$log_file"
#获取当前计算机配置
cpu_info=$(lscpu | grep "Model name" | awk -F: '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
echo "当前计算机配置: $cpu_info" | tee -a "$log_file"
echo "模型: $model" | tee -a "$log_file"
echo "prompt: $prompt" | tee -a "$log_file"
printf "耗时: %.3f 秒\n" $duration | tee -a "$log_file"

# 统计 token 数和生成速度
# 提取 response 字段内容并计算长度
response_text=$(echo "$body" | grep -o '"response":"[^"]*"' | sed 's/"response":"\(.*\)"/\1/' | sed 's/\\n/ /g')
char_count=$(echo -n "$response_text" | wc -c)
if [ "$duration" != "0" ]; then
  speed=$(LC_ALL=C echo "$char_count / $duration" | bc -l)
else
  speed=0
fi
echo "生成字符数: $char_count" | tee -a "$log_file"
printf "平均生成速度: %.2f 字符/秒\n" $speed | tee -a "$log_file"

exit 0