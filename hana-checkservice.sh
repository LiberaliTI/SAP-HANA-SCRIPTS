#!/bin/bash

# Script: hana-checkservice.sh
# Descrição: Script para gerenciamento e inicialização do SAP HANA e serviços SAP B1 no SUSE Linux
# Autor: Guilherme Romera TI/LIBERALI
# Data: 23/04/2025
#
# Este script verifica e gerencia a inicialização automática dos serviços
# e garante a inicialização correta do SAP HANA antes dos serviços SAP B1

# Definição de variáveis
HANA_USER="hdbadm"
HANA_INSTANCE="00"  # Número da instância SAP HANA
MAX_RETRIES=20      # Número máximo de tentativas para verificar se o banco está online
RETRY_INTERVAL=20   # Intervalo em segundos entre as verificações
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"  # Diretório do script
LOG_FILE="$SCRIPT_DIR/hana-checkservice.log"  # Arquivo de log
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"  # Caminho completo do script
SERVICE_NAME="hana-checkservice.service"  # Nome do serviço systemd
HANA_SERVICE="sapinit"  # Nome do serviço do SAP HANA
BASH_PATH="/bin/bash"  # Caminho completo para o bash

# Verificar se o script existe
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "ERRO: Script não encontrado em $SCRIPT_PATH"
    exit 1
fi

# Garantir que o script tem permissões de execução
chmod +x "$SCRIPT_PATH"

# Serviços que precisam ser verificados
SERVICES=(
    "sapinit"
    "sapb1servertools"
    "sapb1servertools-authentication"
)

# Função para registrar mensagens no log
log_message() {
    # Garantir que o arquivo de log existe e tem as permissões corretas
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Função para verificar se um serviço está configurado para iniciar automaticamente
check_service_autostart() {
    local service=$1
    systemctl is-enabled "$service" > /dev/null 2>&1
    return $?
}

# Função para desabilitar a inicialização automática de um serviço
disable_service_autostart() {
    local service=$1
    systemctl disable "$service" > /dev/null 2>&1
    return $?
}

# Função para verificar se um serviço está ativo
check_service_status() {
    local service=$1
    systemctl is-active "$service" > /dev/null 2>&1
    return $?
}

# Função para verificar se o serviço do SAP HANA está rodando
check_hana_service() {
    log_message "Verificando status do serviço $HANA_SERVICE..."
    if systemctl is-active "$HANA_SERVICE" > /dev/null 2>&1; then
        log_message "Serviço $HANA_SERVICE está ativo."
        return 0
    else
        log_message "Serviço $HANA_SERVICE não está ativo."
        return 1
    fi
}

# Função para iniciar o serviço do SAP HANA
start_hana_service() {
    log_message "Iniciando serviço $HANA_SERVICE..."
    systemctl start "$HANA_SERVICE"
    if [ $? -eq 0 ]; then
        log_message "Serviço $HANA_SERVICE iniciado com sucesso."
        return 0
    else
        log_message "ERRO: Falha ao iniciar o serviço $HANA_SERVICE."
        return 1
    fi
}

# Função para verificar se o SAP HANA está online
check_hana_status() {
    log_message "Verificando status do SAP HANA..."
    
    # Primeiro verificar se o serviço está rodando
    if ! check_hana_service; then
        log_message "Serviço $HANA_SERVICE não está ativo. Tentando iniciar..."
        if ! start_hana_service; then
            return 1
        fi
        # Aguardar um pouco para o serviço iniciar
        sleep 30
    fi
    
    # Tentar conectar ao SAP HANA
    local output
    output=$(su - $HANA_USER -c "sapcontrol -nr $HANA_INSTANCE -function GetProcessList" 2>&1)
    local status=$?
    
    if [ $status -eq 0 ] && echo "$output" | grep -q "GREEN"; then
        log_message "SAP HANA está online."
        return 0
    else
        log_message "ERRO: Falha ao conectar ao SAP HANA. Saída: $output"
        return 1
    fi
}

# Função para verificar se o script está configurado para iniciar automaticamente
check_script_autostart() {
    if [ ! -f "/etc/systemd/system/$SERVICE_NAME" ]; then
        return 1
    fi
    systemctl is-enabled "$SERVICE_NAME" > /dev/null 2>&1
    return $?
}

# Função para configurar o script para iniciar automaticamente
setup_autostart() {
    log_message "Configurando inicialização automática do script..."
    
    # Remover serviço existente se houver
    if [ -f "/etc/systemd/system/$SERVICE_NAME" ]; then
        systemctl stop "$SERVICE_NAME" > /dev/null 2>&1
        systemctl disable "$SERVICE_NAME" > /dev/null 2>&1
        rm -f "/etc/systemd/system/$SERVICE_NAME"
    fi
    
    # Criar arquivo de serviço systemd
    cat > "/etc/systemd/system/$SERVICE_NAME" << EOF
[Unit]
Description=SAP HANA and B1 Services Check and Start
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$BASH_PATH $SCRIPT_PATH
Restart=no
TimeoutSec=0
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # Recarregar systemd e habilitar o serviço
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    # Verificar se o serviço foi configurado corretamente
    if systemctl is-enabled "$SERVICE_NAME" > /dev/null 2>&1; then
        log_message "Serviço $SERVICE_NAME configurado com sucesso."
        return 0
    else
        log_message "ERRO: Falha ao configurar o serviço $SERVICE_NAME."
        return 1
    fi
}

# Função para verificar se todos os serviços estão rodando
check_all_services() {
    log_message "Verificando status de todos os serviços..."
    
    # Verificar SAP HANA
    if ! check_hana_status; then
        log_message "SAP HANA não está online."
        return 1
    fi

    # Verificar todos os serviços
    for service in "${SERVICES[@]}"; do
        if ! check_service_status "$service"; then
            log_message "Serviço $service não está ativo."
            return 1
        fi
        log_message "Serviço $service está ativo."
    done

    log_message "Todos os serviços estão ativos."
    return 0
}

# Função para verificar e gerenciar a inicialização automática dos serviços
manage_service_autostart() {
    local changes_made=0
    log_message "Verificando inicialização automática dos serviços..."
    
    for service in "${SERVICES[@]}"; do
        if check_service_autostart "$service"; then
            log_message "Desabilitando inicialização automática do serviço $service..."
            if disable_service_autostart "$service"; then
                changes_made=1
                log_message "Inicialização automática do serviço $service desabilitada."
            else
                log_message "ERRO: Falha ao desabilitar inicialização automática do serviço $service."
            fi
        fi
    done
    
    return $changes_made
}

# Função para iniciar o SAP HANA
start_hana() {
    log_message "Iniciando o banco de dados SAP HANA..."
    
    # Primeiro verificar se o serviço está rodando
    if ! check_hana_service; then
        if ! start_hana_service; then
            log_message "ERRO: Não foi possível iniciar o serviço $HANA_SERVICE."
            return 1
        fi
        # Aguardar um pouco para o serviço iniciar
        sleep 30
    fi
    
    # Tentar iniciar o SAP HANA
    log_message "Executando comando para iniciar o SAP HANA..."
    local output
    output=$(su - $HANA_USER -c "sapcontrol -nr $HANA_INSTANCE -function Start" 2>&1)
    local status=$?
    
    if [ $status -ne 0 ]; then
        log_message "ERRO: Falha ao iniciar o SAP HANA. Saída: $output"
        return 1
    fi
    
    log_message "Aguardando o SAP HANA ficar online..."
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if check_hana_status; then
            log_message "SAP HANA está online e pronto."
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_message "Tentativa $retry_count de $MAX_RETRIES. Aguardando $RETRY_INTERVAL segundos..."
        sleep $RETRY_INTERVAL
    done
    
    log_message "ERRO: Tempo limite excedido. SAP HANA não ficou online após $MAX_RETRIES tentativas."
    return 1
}

# Função principal
main() {
    log_message "Iniciando execução do script..."
    
    # Verificar se o serviço já está configurado
    if ! check_script_autostart; then
        log_message "Serviço não configurado. Iniciando configuração..."
        if setup_autostart; then
            log_message "Configuração concluída com sucesso."
            echo "Configurado OK"
            exit 0
        else
            log_message "ERRO: Falha na configuração do serviço."
            echo "ERRO: Falha na configuração"
            exit 1
        fi
    fi

    # Se o serviço já estiver configurado, executar a verificação normal
    log_message "Iniciando verificação de serviços..."
    
    # Verificar se tudo está rodando
    if check_all_services; then
        log_message "Todos os serviços estão rodando."
        echo "Serviços e Base Ok"
        exit 0
    fi

    # Se não estiver tudo rodando, verificar e gerenciar serviços
    if manage_service_autostart; then
        log_message "Configuração de serviços atualizada."
        echo "Configurado OK"
    fi

    # Iniciar o SAP HANA se necessário
    if ! check_hana_status; then
        start_hana
        if [ $? -ne 0 ]; then
            log_message "ERRO: Não foi possível iniciar o SAP HANA."
            exit 1
        fi
        sleep 30
    fi

    # Iniciar os serviços SAP B1
    for service in "${SERVICES[@]}"; do
        if ! check_service_status "$service"; then
            log_message "Iniciando serviço $service..."
            systemctl start "$service"
            if [ $? -ne 0 ]; then
                log_message "ERRO: Falha ao iniciar o serviço $service."
                exit 1
            fi
            sleep 5
        fi
    done

    # Verificar se tudo está rodando após as alterações
    if check_all_services; then
        log_message "Todos os serviços iniciados com sucesso."
        echo "Serviços e Base Ok"
        exit 0
    else
        log_message "ERRO: Não foi possível iniciar todos os serviços."
        exit 1
    fi
}

# Executar a função principal
main
