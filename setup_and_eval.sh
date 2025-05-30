#!/bin/bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    error "请使用root权限运行此脚本"
fi

# 检查Docker是否已安装
check_docker() {
    if command -v docker &> /dev/null; then
        log "Docker 已安装，版本信息："
        docker --version
        return 0
    else
        return 1
    fi
}

# 检查Ollama镜像是否存在
check_ollama_image() {
    if docker images | grep -q "ollama/ollama"; then
        log "Ollama 镜像已存在"
        return 0
    else
        return 1
    fi
}

# 检查Ollama容器状态
check_ollama_container() {
    # 检查容器是否存在且正在运行
    if docker ps -a | grep -q "ollama"; then
        if docker ps | grep -q "ollama"; then
            # 检查端口是否正在监听
            if netstat -tuln | grep -q ":11434 "; then
                log "Ollama 容器已存在且正在运行，端口 11434 已监听"
                return 0
            else
                log "Ollama 容器存在但端口未监听，尝试重启容器"
                docker restart ollama
                sleep 5
                if netstat -tuln | grep -q ":11434 "; then
                    log "Ollama 容器重启成功，端口 11434 已监听"
                    return 0
                else
                    return 1
                fi
            fi
        else
            log "Ollama 容器存在但未运行，尝试启动容器"
            docker start ollama
            sleep 5
            if netstat -tuln | grep -q ":11434 "; then
                log "Ollama 容器启动成功，端口 11434 已监听"
                return 0
            else
                return 1
            fi
        fi
    else
        return 1
    fi
}

# 检查模型是否存在
check_model() {
    local model=$1
    if docker exec ollama ollama list | grep -q "$model"; then
        log "模型 $model 已存在"
        return 0
    else
        return 1
    fi
}

# 安装Docker
if ! check_docker; then
    log "开始安装Docker..."
    sudo yum install docker
else
    log "Docker 已存在，跳过安装步骤"
fi

# 启动Docker服务
log "启动Docker服务..."
sudo systemctl start docker
sudo systemctl enable docker

# 使用Docker安装Ollama
if ! check_ollama_image; then
    log "开始安装Ollama镜像..."
    docker pull ollama/ollama
else
    log "Ollama 镜像已存在，跳过安装步骤"
fi

# 启动Ollama容器
if ! check_ollama_container; then
    log "开始启动Ollama容器..."
    docker run -d \
      --name ollama \
      -p 11434:11434 \
      docker.io/ollama/ollama:latest \
      serve
else
    log "Ollama 容器已正常运行，跳过启动步骤"
fi

# 等待Ollama服务完全启动
log "等待Ollama服务启动..."
sleep 10

# 下载模型
models=("qwen3:8b" "qwen3:4b" "qwen3:1.7b")

for model in "${models[@]}"; do
    if ! check_model "$model"; then
        log "开始下载模型: $model"
        sudo docker exec -it ollama ollama pull $model
    else
        log "模型 $model 已存在，跳过下载步骤"
    fi
done

# 确保eval_model.sh有执行权限
sudo chmod +x eval_model.sh

# 依次测试每个模型
for model in "${models[@]}"; do
    log "开始测试模型: $model"
    sudo ./eval_model.sh "$model"
done

log "所有任务完成！" 