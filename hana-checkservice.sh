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
SCRIPT_PATH="/opt/SAP-HANA-SCRIPTS/hana-checkservice.sh"  # Caminho completo do script

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

# Função para verificar se o SAP HANA está online
check_hana_status() {
    su - $HANA_USER -c "sapcontrol -nr $HANA_INSTANCE -function GetProcessList" | grep -q "GREEN"
    return $?
}

# Função para verificar se o script está configurado para iniciar automaticamente
check_script_autostart() {
    if [ ! -f "/etc/systemd/system/hana-checkservice.service" ]; then
        return 1
    fi
    systemctl is-enabled hana-checkservice.service > /dev/null 2>&1
    return $?
}

# Função para configurar o script para iniciar automaticamente
setup_autostart() {
    # Criar arquivo de serviço systemd
    cat > /etc/systemd/system/hana-checkservice.service << EOF
[Unit]
Description=SAP HANA and B1 Services Check and Start
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$SCRIPT_PATH
Restart=no
TimeoutSec=0
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # Recarregar systemd e habilitar o serviço
    systemctl daemon-reload
    systemctl enable hana-checkservice.service
    systemctl start hana-checkservice.service
}

# Função para verificar se todos os serviços estão rodando
check_all_services() {
    # Verificar SAP HANA
    if ! check_hana_status; then
        return 1
    fi

    # Verificar todos os serviços
    for service in "${SERVICES[@]}"; do
        if ! check_service_status "$service"; then
            return 1
        fi
    done

    return 0
}

# Função para verificar e gerenciar a inicialização automática dos serviços
manage_service_autostart() {
    local changes_made=0
    
    for service in "${SERVICES[@]}"; do
        if check_service_autostart "$service"; then
            if disable_service_autostart "$service"; then
                changes_made=1
            fi
        fi
    done
    
    return $changes_made
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

# Função principal
main() {
    # Verificar se é a primeira execução
    if [ "$1" == "--setup" ]; then
        if ! check_script_autostart; then
            setup_autostart
            echo "Configurado OK"
            exit 0
        else
            echo "Já configurado"
            exit 0
        fi
    fi

    # Verificar se tudo está rodando
    if check_all_services; then
        echo "Serviços e Base Ok"
        exit 0
    fi

    # Se não estiver tudo rodando, verificar e gerenciar serviços
    if manage_service_autostart; then
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
            systemctl start "$service"
            sleep 5
        fi
    done

    # Verificar se tudo está rodando após as alterações
    if check_all_services; then
        echo "Serviços e Base Ok"
    else
        log_message "ERRO: Não foi possível iniciar todos os serviços."
        exit 1
    fi
}

# Executar a função principal
main "$@"
