# Script: saphana.sh
# Descrição: Script para inicialização do SAP HANA e serviços SAP B1 no SUSE Linux
# Autor: Guilherme Romera TI/LIBERALI
# Data: 23/04/2025
#
# Este script verifica se o banco de dados SAP HANA está online
# antes de iniciar os serviços SAP B1 com delay

# Definição de variáveis
HANA_USER="hdbadm"
HANA_INSTANCE="00"  # Número da instância SAP HANA
MAX_RETRIES=20      # Número máximo de tentativas para verificar se o banco está online
RETRY_INTERVAL=20   # Intervalo em segundos entre as verificações
LOG_FILE="/opt/hana-checkservice.log"  # Arquivo de log

# Função para registrar mensagens no log
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Função para verificar se o SAP HANA está online
check_hana_status() {
    # Executar o comando sapcontrol para verificar o status dos processos
    su - $HANA_USER -c "sapcontrol -nr $HANA_INSTANCE -function GetProcessList" | grep -q "GREEN"
    return $?
}

# Função para iniciar o SAP HANA
start_hana() {
    log_message "Iniciando o banco de dados SAP HANA..."
    
    # Verificar se o SAP HANA já está em execução
    if check_hana_status; then
        log_message "SAP HANA já está em execução."
        return 0
    fi
    
    # Iniciar o SAP HANA
    log_message "Executando comando para iniciar o SAP HANA..."
    su - $HANA_USER -c "sapcontrol -nr $HANA_INSTANCE -function Start"
    
    # Verificar se o comando foi executado com sucesso
    if [ $? -ne 0 ]; then
        log_message "ERRO: Falha ao iniciar o SAP HANA."
        return 1
    fi
    
    # Aguardar até que o SAP HANA esteja online
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
    
    # Iniciar o serviço sapb1servertools
    log_message "Iniciando sapb1servertools..."
    systemctl start sapb1servertools
    
    # Verificar se o serviço foi iniciado com sucesso
    if [ $? -ne 0 ]; then
        log_message "ERRO: Falha ao iniciar sapb1servertools."
        return 1
    fi
    
    # Aguardar alguns segundos antes de iniciar o próximo serviço
    log_message "Aguardando 5 segundos antes de iniciar o próximo serviço..."
    sleep 5
    
    # Iniciar o serviço sapb1servertools-authentication
    log_message "Iniciando sapb1servertools-authentication..."
    systemctl start sapb1servertools-authentication.service
    
    # Verificar se o serviço foi iniciado com sucesso
    if [ $? -ne 0 ]; then
        log_message "ERRO: Falha ao iniciar sapb1servertools-authentication."
        return 1
    fi
    
    log_message "Todos os serviços SAP B1 foram iniciados com sucesso."
    return 0
}

# Função principal
main() {
    log_message "Iniciando script de inicialização do SAP HANA e serviços SAP B1..."
    
    # Iniciar o SAP HANA
    start_hana
    
    # Verificar se o SAP HANA foi iniciado com sucesso
    if [ $? -ne 0 ]; then
        log_message "ERRO: Não foi possível iniciar o SAP HANA. Abortando a inicialização dos serviços SAP B1."
        exit 1
    fi
    
    # Aguardar um tempo adicional para garantir que o banco esteja completamente pronto
    log_message "SAP HANA iniciado com sucesso. Aguardando 30 segundos adicionais para estabilização..."
    sleep 30
    
    # Iniciar os serviços SAP B1
    start_sapb1_services
    
    # Verificar se os serviços SAP B1 foram iniciados com sucesso
    if [ $? -ne 0 ]; then
        log_message "ERRO: Não foi possível iniciar os serviços SAP B1."
        exit 1
    fi
    
    log_message "Inicialização do SAP HANA e serviços SAP B1 concluída com sucesso."
    exit 0
}

# Executar a função principal
main
