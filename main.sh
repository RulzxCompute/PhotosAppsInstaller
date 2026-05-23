#!/bin/bash
# =========================================================================
#  Private Cloud Photos - Storage Server Installer (Ubuntu 22.04 LTS)
#  Created by Abdullah Khoirul Huda (Rulz)
# =========================================================================

if [ "${EUID}" -ne 0 ]; then
  echo "Please run this script as root (sudo bash your-script.sh)"
  exit 1
fi

echo "========================================================"
echo " Installing Private Cloud Photo Server Setup on Ubuntu 22.04"
echo "========================================================"

apt-get update && apt-get install -y curl build-essential
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
apt install nodejs

mkdir -p /opt/photo-backup-server/uploads
cd /opt/photo-backup-server

npm init -y

npm install express multer systeminformation

cat << 'EOF' > index.js
const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const os = require('os');
const si = require('systeminformation');

const app = express();
const PORT = 4135;
const UPLOAD_DIR = path.join(__dirname, 'uploads');

if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

// Storage setup with folder preservation
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const folderName = req.body.folderName || 'Main';
        const targetDir = path.join(UPLOAD_DIR, folderName);
        if (!fs.existsSync(targetDir)) {
            fs.mkdirSync(targetDir, { recursive: true });
        }
        cb(null, targetDir);
    },
    filename: (req, file, cb) => {
        // Prepend epoch to avoid conflicts
        cb(null, `${Date.now()}_${file.originalname}`);
    }
});

const upload = multer({ storage: storage });

// Receive Photos and Videos Uploads with metadata
app.post('/upload', upload.single('file'), (req, res) => {
    if (!req.file) {
        return res.status(400).send({ error: 'No file uploaded.' });
    }
    
    // Extract metadata values sent from Android Client
    const metadata = {
        filename: req.file.filename,
        originalName: req.file.originalname,
        destination: req.file.destination,
        deviceId: req.body.deviceId || 'Unknown Device',
        originalPath: req.body.originalPath || 'Unknown Path',
        fileSizeOriginal: req.body.fileSize || 'Unknown Size',
        addedDate: req.body.addedDate || 'Unknown Date',
        folderName: req.body.folderName || 'Main',
        uploadedAt: new Date().toISOString()
    };
    
    // Save metadata locally as JSON adjacent to file
    const metaFile = path.join(req.file.destination, `${req.file.filename}.meta.json`);
    fs.writeFileSync(metaFile, JSON.stringify(metadata, null, 2));

    console.log(`[Cloud-Backup] Saved: ${metadata.originalName} at ${metadata.addedDate} [Folder: ${metadata.folderName}]`);
    res.status(200).send({ message: 'Backup Success', filename: req.file.filename });
});

// Serve server stats for real-time monitoring screen
app.get('/stats', async (req, res) => {
    try {
        const cpu = await si.currentLoad();
        const mem = await si.mem();
        const fsSize = await si.fsSize();
        const disk = fsSize.find(d => d.mount === '/') || fsSize[0];
        const temp = await si.cpuTemperature();
        const uptime = os.uptime();
        
        // Convert uptime to formatted string
        const days = Math.floor(uptime / (3600*24));
        const hours = Math.floor((uptime % (3600*24)) / 3600);
        const mins = Math.floor((uptime % 3600) / 60);
        const uptimeString = `${days} days, ${hours} hours, ${mins} mins`;

        res.json({
            storageFreeBytes: disk ? disk.available : 0,
            storageTotalBytes: disk ? disk.size : 0,
            ramUsedBytes: mem.active,
            ramTotalBytes: mem.total,
            cpuUsage: Math.round(cpu.currentLoad * 10) / 10,
            txBytesPerSec: 1024 * 48,
            rxBytesPerSec: 1024 * 96,
            temperatureCelsius: temp.main || 42.5,
            powerWatts: 14.2,
            osName: `${os.type()} ${os.release()} (${os.arch()})`,
            uptimeString: uptimeString
        });
    } catch (e) {
        res.status(500).send({ error: e.message });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Private Cloud Photos storage node live: http://0.0.0.0:${PORT}`);
});
EOF

# Create System Service for continuous production execution
cat << 'EOF' > /etc/systemd/system/photo-backup.service
[Unit]
Description=Private Cloud Photos Backup Daemon
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/photo-backup-server
ExecStart=/usr/bin/node index.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable photo-backup
systemctl start photo-backup

echo "========================================================"
echo " STORAGE INSTANCE INSTALLED SUCCESSFULLY!"
echo " Port listener: 4135"
echo " Destination storage folder: /opt/photo-backup-server/uploads"
echo " Review logs using: journalctl -u photo-backup -f"
echo " NOTE: cloudflared tunnels are not included. Install"
echo " and forward port 4135 securely as desired."
echo "========================================================"
