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
LOG_FILE="/opt/hana-checkservice.log"  # Arquivo de log

# Serviços que precisam ser verificados
SERVICES=(
    "sapb1servertools"
    "sapb1servertools-authentication"
    "sapinit"
)

# Função para registrar mensagens no log
log_message() {
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
    log_message "Desabilitando inicialização automática do serviço $service..."
    systemctl disable "$service"
    if [ $? -eq 0 ]; then
        log_message "Serviço $service desabilitado com sucesso."
        return 0
    else
        log_message "ERRO: Falha ao desabilitar o serviço $service."
        return 1
    fi
}

# Função para verificar se o SAP HANA está online
check_hana_status() {
    su - $HANA_USER -c "sapcontrol -nr $HANA_INSTANCE -function GetProcessList" | grep -q "GREEN"
    return $?
}

# Função para iniciar o SAP HANA
start_hana() {
    log_message "Iniciando o banco de dados SAP HANA..."
    
    if check_hana_status; then
        log_message "SAP HANA já está em execução."
        return 0
    fi
    
    log_message "Executando comando para iniciar o SAP HANA..."
    su - $HANA_USER -c "sapcontrol -nr $HANA_INSTANCE -function Start"
    
    if [ $? -ne 0 ]; then
        log_message "ERRO: Falha ao iniciar o SAP HANA."
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

# Função para iniciar os serviços SAP B1
start_sapb1_services() {
    log_message "Iniciando os serviços SAP B1..."
    
    for service in "${SERVICES[@]}"; do
        log_message "Iniciando $service..."
        systemctl start "$service"
        
        if [ $? -ne 0 ]; then
            log_message "ERRO: Falha ao iniciar $service."
            return 1
        fi
        
        log_message "Aguardando 5 segundos antes do próximo serviço..."
        sleep 5
    done
    
    log_message "Todos os serviços SAP B1 foram iniciados com sucesso."
    return 0
}

# Função para verificar e gerenciar a inicialização automática dos serviços
manage_service_autostart() {
    log_message "Verificando configuração de inicialização automática dos serviços..."
    
    for service in "${SERVICES[@]}"; do
        if check_service_autostart "$service"; then
            log_message "Serviço $service está configurado para iniciar automaticamente."
            disable_service_autostart "$service"
            if [ $? -ne 0 ]; then
                log_message "AVISO: Não foi possível desabilitar a inicialização automática do $service."
            fi
        else
            log_message "Serviço $service já está com inicialização automática desabilitada."
        fi
    done
}

# Função principal
main() {
    log_message "Iniciando script de gerenciamento do SAP HANA e serviços SAP B1..."
    
    # Verificar e gerenciar a inicialização automática dos serviços
    manage_service_autostart
    
    # Iniciar o SAP HANA
    start_hana
    
    if [ $? -ne 0 ]; then
        log_message "ERRO: Não foi possível iniciar o SAP HANA. Abortando a inicialização dos serviços SAP B1."
        exit 1
    fi
    
    log_message "SAP HANA iniciado com sucesso. Aguardando 30 segundos para estabilização..."
    sleep 30
    
    # Iniciar os serviços SAP B1
    start_sapb1_services
    
    if [ $? -ne 0 ]; then
        log_message "ERRO: Não foi possível iniciar os serviços SAP B1."
        exit 1
    fi
    
    log_message "Inicialização do SAP HANA e serviços SAP B1 concluída com sucesso."
    exit 0
}

# Executar a função principal
main
