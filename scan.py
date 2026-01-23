import socket
import sys
from tqdm import tqdm
from multiprocessing.pool import ThreadPool

# Импортируем словарь портов из отдельного файла
try:
    from services import PORT_SERVICES
except ImportError:
    # Если файл не найден, создаем минимальный словарь
    PORT_SERVICES = {
        21: "FTP",
        22: "SSH",
        23: "Telnet",
        80: "HTTP",
        443: "HTTPS",
        3306: "MySQL",
        5432: "PostgreSQL",
        8080: "HTTP-Proxy",
    }

# Запрашиваем хост с терминала
if len(sys.argv) > 1:
    HOST = sys.argv[1]
else:
    HOST = input("Введите хост для сканирования: ")

PORTS_COUNT = 2 ** 16
TIMEOUT = 1


def is_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(TIMEOUT)
        return None if sock.connect_ex((HOST, port)) else port


if __name__ == '__main__':
    pool = ThreadPool(3000)
    scanned = list(
        tqdm(pool.imap(is_open, range(1, PORTS_COUNT)), total=PORTS_COUNT - 1, desc=f"Scanning {HOST}"))

    # Фильтруем открытые порты
    open_ports = [port for port in scanned if port]

    if not open_ports:
        print("Открытых портов нет")
    else:
        print("Открытые порты:")
        for port in open_ports:
            service = PORT_SERVICES.get(port, "Unknown")
            print(f"  {port}: {service}")