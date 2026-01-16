#!/usr/bin/env python3
"""
Простой Samba-клиент для сканирования сети на наличие публичных шаров
"""

import subprocess
import ipaddress
import socket
import concurrent.futures
import argparse
import sys
from datetime import datetime

def check_host_alive(ip, timeout=1):
    """Проверяет, жив ли хост с помощью ping"""
    try:
        # Для Ubuntu используем ping с ограничением по времени
        result = subprocess.run(
            ['ping', '-c', '1', '-W', str(timeout), str(ip)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout + 1
        )
        return result.returncode == 0
    except:
        return False

def check_smb_port(ip, port=445, timeout=2):
    """Проверяет, открыт ли SMB порт на хосте"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((str(ip), port))
        sock.close()
        return result == 0
    except:
        return False

def check_public_shares(ip):
    """Проверяет наличие публичных шаров на хосте"""
    try:
        # Пробуем подключиться без пароля (как гость)
        result = subprocess.run(
            ['smbclient', '-L', str(ip), '-N', '-U', 'guest%'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10
        )
        
        # Также пробуем с пустым паролем
        result_empty = subprocess.run(
            ['smbclient', '-L', str(ip), '-N'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10
        )
        
        output = result.stdout.decode('utf-8', errors='ignore')
        output_empty = result_empty.stdout.decode('utf-8', errors='ignore')
        
        shares = []
        
        # Ищем шары в выводе smbclient
        for line in output.split('\n') + output_empty.split('\n'):
            if 'Disk' in line and not 'IPC' in line:
                parts = line.split()
                if len(parts) > 0:
                    share_name = parts[0].strip()
                    if share_name and not share_name.startswith('\\'):
                        shares.append(share_name)
        
        return list(set(shares))  # Удаляем дубликаты
        
    except subprocess.TimeoutExpired:
        return []
    except Exception as e:
        return []

def scan_network(network, max_workers=50):
    """Сканирует сеть на наличие хостов с публичными SMB-шарами"""
    print(f"[*] Начинаю сканирование сети: {network}")
    print(f"[*] Время начала: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("-" * 60)
    
    try:
        net = ipaddress.ip_network(network, strict=False)
    except ValueError as e:
        print(f"[!] Ошибка: Неверный формат сети. Пример: 192.168.1.0/24")
        return
    
    hosts_with_shares = []
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Сначала проверяем доступность хостов
        future_to_ip = {executor.submit(check_host_alive, ip): ip for ip in net.hosts()}
        
        for future in concurrent.futures.as_completed(future_to_ip):
            ip = future_to_ip[future]
            try:
                is_alive = future.result()
                if is_alive:
                    # Проверяем SMB порт
                    if check_smb_port(ip):
                        print(f"[+] Хост {ip} доступен и имеет открытый SMB порт")
                        
                        # Проверяем публичные шары
                        shares = check_public_shares(ip)
                        if shares:
                            print(f"[!] НАЙДЕНЫ публичные шары на {ip}:")
                            for share in shares:
                                print(f"    \\\\{ip}\\{share}")
                            hosts_with_shares.append((ip, shares))
                        else:
                            print(f"[-] Хост {ip}: публичные шары не найдены")
                else:
                    print(f"[-] Хост {ip} не отвечает")
                    
            except Exception as e:
                print(f"[!] Ошибка при проверке {ip}: {e}")
    
    print("-" * 60)
    print(f"[*] Сканирование завершено: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    if hosts_with_shares:
        print(f"\n[+] ИТОГ: Найдено {len(hosts_with_shares)} хостов с публичными шарами:")
        for ip, shares in hosts_with_shares:
            print(f"    {ip}: {', '.join(shares)}")
    else:
        print(f"\n[-] Публичные шары не найдены в сети {network}")

def main():
    parser = argparse.ArgumentParser(
        description='Сканер SMB-шаров для поиска публичных ресурсов в сети',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Примеры использования:
  %(prog)s 192.168.1.0/24     # Сканировать всю сеть 192.168.1.0/24
  %(prog)s 10.0.0.0/24        # Сканировать сеть 10.0.0.0/24
  %(prog)s 172.16.1.0/24 -t 100  # Использовать 100 потоков
        '''
    )
    
    parser.add_argument('network', help='Сеть для сканирования (например: 192.168.1.0/24)')
    parser.add_argument('-t', '--threads', type=int, default=50,
                       help='Количество потоков (по умолчанию: 50)')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Подробный вывод')
    
    args = parser.parse_args()
    
    print("""
╔══════════════════════════════════════════════════════════╗
║             Simple SMB Public Share Scanner              ║
║                    (для Ubuntu VBox)                     ║
╚══════════════════════════════════════════════════════════╝
""")
    
    scan_network(args.network, args.threads)

if __name__ == "__main__":
    main()

