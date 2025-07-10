#!/usr/bin/env python3

import requests
import time
import subprocess
from datetime import datetime
import xml.etree.ElementTree as ET

# --- CONFIGURAÇÕES ---
PLEX_URL = "http://localhost:32400"  # Onde o script pode acessar o Plex Media Server
PLEX_TOKEN = "_bdzm4yeuQG_2JzsjZZT"  # <--- SUBSTITUA PELO SEU TOKEN REAL DO PLEX!
MONITOR_INTERVAL_SECONDS = 30        # Frequência de verificação (a cada 30 segundos)
LOG_FILE = "/var/log/plex_activity_monitor.log"  # Onde o script vai registrar suas ações

# --- Variável global para o processo de inibição ---
inhibit_process = None

# --- Função de Log ---
def log(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] {message}"
    print(log_entry)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(log_entry + "\n")
    except IOError as e:
        print(f"[{timestamp}] ERRO: Não foi possível escrever no arquivo de log {LOG_FILE}: {e}")

# --- Função para Obter Streams Ativas do Plex ---
def get_active_plex_streams():
    headers = {"X-Plex-Token": PLEX_TOKEN, "Accept": "application/xml"}
    try:
        response = requests.get(f"{PLEX_URL}/status/sessions", headers=headers, timeout=10)
        response.raise_for_status()
        xml_content = response.text
        root = ET.fromstring(xml_content)
        active_streams = int(root.get('size', 0))
        if active_streams > 0:
            log(f"DEBUG: Encontrado {active_streams} stream(s) ativa(s).")
        else:
            log("DEBUG: Nenhuma stream ativa detectada (size=0).")
        return active_streams
    except Exception as e:
        log(f"Erro ao obter streams do Plex: {e}")
        return 0

# --- Funções para Gerenciar Inibição de Suspensão ---
def start_inhibit():
    global inhibit_process
    if inhibit_process is None or inhibit_process.poll() is not None:
        log("Iniciando inibidor de suspensão...")
        try:
            inhibit_process = subprocess.Popen([
                "systemd-inhibit", "--what=sleep",
                "--who=Plex Activity Monitor",
                "--why=Plex streaming activity detected",
                "sleep", "infinity"
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            log(f"Processo de inibição iniciado (PID: {inhibit_process.pid}).")
        except Exception as e:
            log(f"ERRO ao iniciar o processo de inibição: {e}")

def stop_inhibit():
    global inhibit_process
    if inhibit_process and inhibit_process.poll() is None:
        log("Parando inibidor de suspensão...")
        inhibit_process.terminate()
        try:
            inhibit_process.wait(timeout=5)
            log("Inibidor de suspensão parado com sucesso.")
        except subprocess.TimeoutExpired:
            inhibit_process.kill()
            log("Inibidor de suspensão forçado a parar (timeout expirado).")
        inhibit_process = None
    elif inhibit_process and inhibit_process.poll() is not None:
        log("Inibidor de suspensão já havia parado.")
        inhibit_process = None

# --- Função Principal do Monitor ---
def main():
    log("Iniciando monitor de atividade do Plex Media Server.")
    is_inhibitor_active = False
    while True:
        try:
            active_streams = get_active_plex_streams()
            if active_streams > 0:
                if not is_inhibitor_active:
                    log(f"Atividade de streaming detectada ({active_streams} streams). Ativando inibição.")
                    start_inhibit()
                    is_inhibitor_active = True
                else:
                    log(f"Atividade de streaming contínua ({active_streams} streams). Inibição mantida.")
                    if inhibit_process is None or inhibit_process.poll() is not None:
                        log("Aviso: Processo de inibição parou inesperadamente. Reiniciando...")
                        start_inhibit()
            else:
                if is_inhibitor_active:
                    log("Nenhuma atividade de streaming detectada. Desativando inibição.")
                    stop_inhibit()
                    is_inhibitor_active = False
                else:
                    log("Nenhuma atividade de streaming detectada. Permanecendo inativo.")
            time.sleep(MONITOR_INTERVAL_SECONDS)
        except KeyboardInterrupt:
            log("Script encerrado pelo usuário (Ctrl+C).")
            stop_inhibit()
            break
        except Exception as e:
            log(f"ERRO INESPERADO NO LOOP PRINCIPAL: {e}")
            stop_inhibit()
            time.sleep(MONITOR_INTERVAL_SECONDS * 2)

# --- Ponto de Entrada do Script ---
if __name__ == "__main__":
    inhibit_process = None
    try:
        main()
    except Exception as e:
        log(f"Erro fatal na execução do script: {e}")
    finally:
        stop_inhibit()
