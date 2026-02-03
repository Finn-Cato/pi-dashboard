#!/bin/bash
# Super Simple Pi Agent Installer - Copy and paste this entire script!

echo "Installing Pi Dashboard Agent..."

# Create directory and agent script
mkdir -p ~/pi-agent
cat > ~/pi-agent/pi_agent.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, request, jsonify
import subprocess, os, socket
from datetime import datetime

app = Flask(__name__)

def get_config_path():
    for path in ["/boot/fullpageos.txt", "/boot/firmware/fullpageos.txt"]:
        if os.path.exists(path): return path
    return None

def run_command(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return {'success': True, 'output': result.stdout.strip(), 'error': result.stderr.strip()}
    except Exception as e:
        return {'success': False, 'error': str(e)}

@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'timestamp': datetime.now().isoformat()})

@app.route('/status')
def status():
    config_path = get_config_path()
    current_url = "Unknown"
    if config_path:
        try:
            with open(config_path, 'r') as f:
                current_url = f.readline().strip()
        except: pass
    return jsonify({
        'hostname': socket.gethostname(),
        'uptime': run_command("uptime -p").get('output', 'Unknown'),
        'current_url': current_url,
        'memory': run_command("free -h | grep Mem | awk '{print $3\"/\"$2}'").get('output', 'Unknown'),
        'temperature': run_command("vcgencmd measure_temp | cut -d= -f2").get('output', 'Unknown'),
        'cpu_usage': run_command("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1").get('output', 'Unknown'),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/url', methods=['POST'])
def change_url():
    new_url = request.get_json().get('url')
    if not new_url: return jsonify({'success': False, 'error': 'No URL'}), 400
    config_path = get_config_path()
    if not config_path: return jsonify({'success': False, 'error': 'Config not found'}), 500
    try:
        # Simply overwrite the entire file with just the new URL
        with open(config_path, 'w') as f:
            f.write(f'{new_url}\n')
        return jsonify({'success': True, 'message': f'URL updated to {new_url}', 'new_url': new_url})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/restart-browser', methods=['POST'])
def restart_browser():
    result = run_command("sudo systemctl restart fullpageos")
    return jsonify({'success': result['success'], 'message': 'Browser restarted' if result['success'] else result.get('error')})

@app.route('/reboot', methods=['POST'])
def reboot():
    subprocess.Popen(['sudo', 'shutdown', '-r', '+0.1'])
    return jsonify({'success': True, 'message': 'Pi is rebooting...'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

chmod +x ~/pi-agent/pi_agent.py

# Install Flask
pip3 install flask --break-system-packages 2>/dev/null || pip3 install flask

# Create service
sudo tee /etc/systemd/system/pi-agent.service > /dev/null << 'EOF'
[Unit]
Description=Raspberry Pi Dashboard Agent
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/pi-agent
ExecStart=/usr/bin/python3 /home/pi/pi-agent/pi_agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Start service
sudo systemctl daemon-reload
sudo systemctl enable pi-agent
sudo systemctl start pi-agent
sleep 2

# Check status
if sudo systemctl is-active --quiet pi-agent; then
    echo "✅ SUCCESS! Agent is running on port 5000"
    echo "Test it: curl http://localhost:5000/health"
else
    echo "⚠️ Check status: sudo systemctl status pi-agent"
fi
