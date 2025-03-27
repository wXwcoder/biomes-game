# 构建阶段
FROM node:20.9.0-bookworm-slim AS builder

# 1. 强制覆盖所有APT源配置（阿里云镜像）
RUN rm -rf /etc/apt/sources.list.d/* && \
    mkdir -p /etc/apt && \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian/ bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian/ bookworm-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Dl-Limit=100 update && \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Dl-Limit=100 install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates

# 2. 升级为HTTPS源
RUN sed -i 's/http:/https:/g' /etc/apt/sources.list && \
    apt-get -o Acquire::Retries=5 update

# 2. 配置阿里云源并安装基础工具
RUN mkdir -p /etc/apt && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian/ bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian/ bookworm-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Dl-Limit=100 update && \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Dl-Limit=100 install -y --no-install-recommends \
    curl \
    gnupg2 \
    libnss3 \
    && rm -rf /var/lib/apt/lists/*

# 2. 安装系统依赖
RUN apt-get -o Acquire::Retries=5 update && \
    apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
    build-essential \
    python3-full \
    python3-dev \
    zlib1g-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libwebp-dev \
    && rm -rf /var/lib/apt/lists/*

# 3. 设置npm registry（带重试参数）
# 3. 设置npm registry（带重试参数）
ENV NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
#ENV YARN_REGISTRY=https://registry.npmmirror.com
# 修改 corepack 配置
RUN npm install -g corepack@latest --fetch-retries=5 --fetch-retry-mintimeout=20000 \
    && corepack enable \
    && corepack prepare yarn@4.1.0 --activate

# 4. 安装Git LFS（使用修正的阿里云镜像）
# 4. 安装Git LFS（修复镜像路径）
# 方案一：使用官方源带重试参数（推荐）
RUN curl --retry 5 --retry-delay 10 -k -sL https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash -s -- -y os=debian dist=bookworm && \
    apt-get update && \
    apt-get install -y git-lfs && \
    git lfs install

# 方案二：尝试阿里云镜像新路径（备用）
# RUN curl -k -sL https://mirrors.aliyun.com/packagecloud/git-lfs/script.deb.sh | bash -s -- -y os=debian dist=bookworm && \
#    apt-get update && \
#    apt-get install -y git-lfs && \
#    git lfs install
RUN npm config set registry https://registry.npmmirror.com
RUN npm config get registry
# 新增 Bazel 安装步骤
#RUN npm install -g @bazel/bazelisk@latest --registry=https://registry.npmmirror.com

# 5. 创建虚拟环境
RUN python3 -m venv /opt/venv && \
    chown -R node:node /opt/venv && \
    chmod -R 755 /opt/venv

# 6. 配置pip
RUN /opt/venv/bin/pip config set global.index-url https://pypi.org/simple/ && \
    /opt/venv/bin/pip install -U pip wheel setuptools

# 7. 克隆仓库
WORKDIR /app
#RUN git clone https://github.com/ill-inc/biomes-game.git --depth=1 .
COPY . .

# 新增 yarn 配置步骤（在项目目录上下文）
#RUN yarn config set npmRegistryServer https://registry.npmmirror.com \
#    && yarn config set httpRetry 5 \
#    && yarn config set networkTimeout 600000

RUN git lfs pull

# 8. 修改requirements.txt（移除或更新pyinstaller）
RUN sed -i '/pyinstaller==4.8/d' requirements.txt && \
    echo "pyinstaller>=6.0.0" >> requirements.txt

# 9. 安装项目依赖（移除 --user 参数）
RUN /opt/venv/bin/pip install --default-timeout=100 --retries 10 -r requirements.txt

# 修改 yarn 安装步骤，添加镜像源和重试参数
#RUN yarn config set registry https://registry.npmmirror.com
#RUN yarn config set npmRegistryServer https://registry.npmmirror.com \
#    && yarn config set enableImmutableInstalls false \
#    && yarn install --immutable --immutable-cache --network-timeout 600000 --retry 5 \
#    --registry=https://registry.npmmirror.com \
#    --mirror https://registry.npmmirror.com/react-leaflet-markercluster/-/react-leaflet-markercluster-3.0.0-rc.0.tgz


# ===================== 运行阶段 =====================
FROM node:20.9.0-bookworm-slim

# 1. 强制覆盖所有APT源配置（使用HTTP协议）
RUN rm -rf /etc/apt/sources.list.d/* && \
    mkdir -p /etc/apt && \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian/ bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian/ bookworm-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list

# 2. 安装基础证书（添加重试参数）
RUN apt-get -o Acquire::Retries=5 -o Acquire::http::Dl-Limit=100 update && \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Dl-Limit=100 install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates

# 3. 升级为HTTPS源
RUN sed -i 's/http:/https:/g' /etc/apt/sources.list && \
    apt-get -o Acquire::Retries=5 update

# 1. 优先配置阿里云镜像源
RUN mkdir -p /etc/apt && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian/ bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian/ bookworm-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list

# 2. 安装基础证书（必须在配置镜像源之后）
RUN apt-get -o Acquire::Retries=5 update && \
    apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates

# 2. 配置阿里云镜像源并安装运行时依赖（合并到单一步骤）
RUN mkdir -p /etc/apt && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian/ bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian/ bookworm-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] https://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Dl-Limit=100 update && \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Dl-Limit=100 install -y --no-install-recommends \
    python3 \
    git-lfs \
    zlib1g \
    libjpeg62-turbo \
    libpng16-16 \
    libtiff6 \
    libwebp7 \
    rsync \
    && rm -rf /var/lib/apt/lists/*

ENV npm_config_registry=https://registry.npmmirror.com
#ENV YARN_REGISTRY=https://registry.npmmirror.com

RUN npm config set registry https://registry.npmmirror.com
RUN npm config get registry
# 新增 Bazel 安装步骤
RUN npm install -g @bazel/bazelisk@latest --registry=https://registry.npmmirror.com

# 修改 yarn 安装步骤，适配 Yarn Berry
RUN yarn config set npmRegistryServer https://registry.npmmirror.com \
    && yarn config set httpRetry 5 \
    && yarn config set networkTimeout 600000 \
    && yarn config set enableImmutableInstalls false \
    && echo "nodeLinker: node-modules" > .yarnrc.yml \
    && echo "packageManager: yarn@4.1.0" >> .yarnrc.yml \
    && yarn install --immutable

# 2. 复制构建产物
COPY --from=builder --chown=node:node /opt/venv /opt/venv
COPY --from=builder --chown=node:node /app /app

# 5. 删除冗余权限设置（移除以下代码）
# RUN chmod +x /app/b && \
#    chown -R node:node /app

# 3. 设置环境变量前添加权限修复（移除以下代码）
# RUN chown -R node:node /opt/venv && \
#    chmod -R 755 /opt/venv && \
#    chown -R node:node /opt/venv

# 3. 设置环境变量
ENV PATH="/opt/venv/bin:$PATH"
ENV LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

# 4. 初始化Git LFS
RUN git lfs install

# 5. 删除冗余权限设置（此处已移除）

# 6. 使用非root用户
USER node
WORKDIR /app

# 7. 暴露端口
EXPOSE 3000

# 8. 启动命令
CMD ["./b", "data-snapshot", "run"]


