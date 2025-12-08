#!/usr/bin/env python3
"""
Mesh Network Monitor - Notification System
Sends alerts via Email, Telegram, Discord, Slack, and custom webhooks
"""

import smtplib
import requests
import yaml
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Dict, List
from datetime import datetime


class NotificationManager:
    def __init__(self, config: dict):
        self.config = config.get('notifications', {})

    def send_alert(self, alert: Dict):
        """Send alert via all enabled notification channels"""
        results = []

        if self.config.get('email', {}).get('enabled', False):
            results.append(('email', self.send_email(alert)))

        if self.config.get('telegram', {}).get('enabled', False):
            results.append(('telegram', self.send_telegram(alert)))

        if self.config.get('discord', {}).get('enabled', False):
            results.append(('discord', self.send_discord(alert)))

        if self.config.get('slack', {}).get('enabled', False):
            results.append(('slack', self.send_slack(alert)))

        if self.config.get('webhook', {}).get('enabled', False):
            results.append(('webhook', self.send_webhook(alert)))

        return results

    def send_email(self, alert: Dict) -> bool:
        """Send email notification"""
        try:
            email_config = self.config['email']

            # Create message
            msg = MIMEMultipart()
            msg['From'] = email_config['from']
            msg['To'] = ', '.join(email_config['to'])
            msg['Subject'] = self._format_email_subject(alert)

            body = self._format_email_body(alert)
            msg.attach(MIMEText(body, 'plain'))

            # Send via SMTP
            with smtplib.SMTP(email_config['smtp_server'], email_config['smtp_port']) as server:
                server.starttls()
                server.login(email_config['smtp_user'], email_config['smtp_password'])
                server.send_message(msg)

            return True

        except Exception as e:
            print(f"Email notification failed: {e}")
            return False

    def send_telegram(self, alert: Dict) -> bool:
        """Send Telegram notification"""
        try:
            telegram_config = self.config['telegram']
            bot_token = telegram_config['bot_token']
            chat_id = telegram_config['chat_id']

            message = self._format_telegram_message(alert)

            url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
            data = {
                'chat_id': chat_id,
                'text': message,
                'parse_mode': 'Markdown'
            }

            response = requests.post(url, data=data, timeout=10)
            return response.status_code == 200

        except Exception as e:
            print(f"Telegram notification failed: {e}")
            return False

    def send_discord(self, alert: Dict) -> bool:
        """Send Discord webhook notification"""
        try:
            discord_config = self.config['discord']
            webhook_url = discord_config['webhook_url']

            embed = self._format_discord_embed(alert)

            data = {'embeds': [embed]}
            response = requests.post(webhook_url, json=data, timeout=10)
            return response.status_code == 204

        except Exception as e:
            print(f"Discord notification failed: {e}")
            return False

    def send_slack(self, alert: Dict) -> bool:
        """Send Slack webhook notification"""
        try:
            slack_config = self.config['slack']
            webhook_url = slack_config['webhook_url']

            message = self._format_slack_message(alert)

            response = requests.post(webhook_url, json=message, timeout=10)
            return response.status_code == 200

        except Exception as e:
            print(f"Slack notification failed: {e}")
            return False

    def send_webhook(self, alert: Dict) -> bool:
        """Send custom webhook notification"""
        try:
            webhook_config = self.config['webhook']
            url = webhook_config['url']
            method = webhook_config.get('method', 'POST')
            headers = webhook_config.get('headers', {})

            data = {
                'timestamp': alert.get('timestamp', datetime.now().isoformat()),
                'hostname': alert.get('hostname', ''),
                'severity': alert.get('severity', 'unknown'),
                'type': alert.get('type', ''),
                'message': alert.get('message', '')
            }

            if method.upper() == 'POST':
                response = requests.post(url, json=data, headers=headers, timeout=10)
            elif method.upper() == 'PUT':
                response = requests.put(url, json=data, headers=headers, timeout=10)
            else:
                return False

            return response.status_code in [200, 201, 202, 204]

        except Exception as e:
            print(f"Webhook notification failed: {e}")
            return False

    def _format_email_subject(self, alert: Dict) -> str:
        """Format email subject line"""
        severity = alert.get('severity', 'unknown').upper()
        hostname = alert.get('hostname', 'unknown')
        alert_type = alert.get('type', 'alert')

        return f"[{severity}] Mesh Network: {hostname} - {alert_type}"

    def _format_email_body(self, alert: Dict) -> str:
        """Format email body"""
        return f"""Mesh Network Alert

Severity: {alert.get('severity', 'unknown').upper()}
Node: {alert.get('hostname', 'unknown')}
Type: {alert.get('type', 'unknown')}
Time: {alert.get('timestamp', datetime.now())}

Message:
{alert.get('message', 'No details available')}

---
Mesh Network Monitor
View dashboard: http://monitor.mesh.local:8080
"""

    def _format_telegram_message(self, alert: Dict) -> str:
        """Format Telegram message"""
        severity = alert.get('severity', 'unknown')
        emoji = "🔴" if severity == "critical" else "⚠️"

        hostname = alert.get('hostname', 'unknown')
        alert_type = alert.get('type', 'alert')
        message = alert.get('message', 'No details')

        return f"""{emoji} *{severity.upper()}*

*Node:* {hostname}
*Type:* {alert_type}
*Time:* {alert.get('timestamp', 'unknown')}

{message}

[View Dashboard](http://monitor.mesh.local:8080)
"""

    def _format_discord_embed(self, alert: Dict) -> Dict:
        """Format Discord embed"""
        severity = alert.get('severity', 'unknown')

        # Color based on severity
        color_map = {
            'critical': 15158332,  # Red
            'warning': 16776960,   # Yellow
            'info': 3447003        # Blue
        }
        color = color_map.get(severity, 8421504)  # Gray default

        emoji_map = {
            'critical': '🔴',
            'warning': '⚠️',
            'info': 'ℹ️'
        }
        emoji = emoji_map.get(severity, '🔔')

        hostname = alert.get('hostname', 'unknown')
        alert_type = alert.get('type', 'alert')
        message = alert.get('message', 'No details available')

        return {
            'title': f"{emoji} {severity.upper()} - {alert_type}",
            'description': message,
            'color': color,
            'fields': [
                {
                    'name': 'Node',
                    'value': hostname,
                    'inline': True
                },
                {
                    'name': 'Severity',
                    'value': severity.upper(),
                    'inline': True
                },
                {
                    'name': 'Type',
                    'value': alert_type,
                    'inline': True
                }
            ],
            'timestamp': alert.get('timestamp', datetime.now().isoformat()),
            'footer': {
                'text': 'Mesh Network Monitor'
            }
        }

    def _format_slack_message(self, alert: Dict) -> Dict:
        """Format Slack message"""
        severity = alert.get('severity', 'unknown')
        emoji_map = {
            'critical': ':red_circle:',
            'warning': ':warning:',
            'info': ':information_source:'
        }
        emoji = emoji_map.get(severity, ':bell:')

        hostname = alert.get('hostname', 'unknown')
        alert_type = alert.get('type', 'alert')
        message = alert.get('message', 'No details available')

        return {
            'text': f"{emoji} *{severity.upper()}* - Mesh Network Alert",
            'blocks': [
                {
                    'type': 'header',
                    'text': {
                        'type': 'plain_text',
                        'text': f"{emoji} {severity.upper()} - {alert_type}"
                    }
                },
                {
                    'type': 'section',
                    'fields': [
                        {
                            'type': 'mrkdwn',
                            'text': f"*Node:*\n{hostname}"
                        },
                        {
                            'type': 'mrkdwn',
                            'text': f"*Severity:*\n{severity.upper()}"
                        },
                        {
                            'type': 'mrkdwn',
                            'text': f"*Type:*\n{alert_type}"
                        },
                        {
                            'type': 'mrkdwn',
                            'text': f"*Time:*\n{alert.get('timestamp', 'unknown')}"
                        }
                    ]
                },
                {
                    'type': 'section',
                    'text': {
                        'type': 'mrkdwn',
                        'text': f"*Message:*\n{message}"
                    }
                },
                {
                    'type': 'actions',
                    'elements': [
                        {
                            'type': 'button',
                            'text': {
                                'type': 'plain_text',
                                'text': 'View Dashboard'
                            },
                            'url': 'http://monitor.mesh.local:8080'
                        }
                    ]
                }
            ]
        }

    def test_notification(self, notification_type: str) -> bool:
        """Test a specific notification type"""
        test_alert = {
            'timestamp': datetime.now().isoformat(),
            'hostname': 'test-node',
            'severity': 'info',
            'type': 'test',
            'message': 'This is a test notification from Mesh Network Monitor'
        }

        if notification_type == 'email':
            return self.send_email(test_alert)
        elif notification_type == 'telegram':
            return self.send_telegram(test_alert)
        elif notification_type == 'discord':
            return self.send_discord(test_alert)
        elif notification_type == 'slack':
            return self.send_slack(test_alert)
        elif notification_type == 'webhook':
            return self.send_webhook(test_alert)
        else:
            print(f"Unknown notification type: {notification_type}")
            return False


if __name__ == '__main__':
    import sys

    if len(sys.argv) < 2:
        print("Usage: notifications.py <type>")
        print("Types: email, telegram, discord, slack, webhook")
        sys.exit(1)

    # Load config
    with open('/etc/mesh-monitor/config.yml', 'r') as f:
        config = yaml.safe_load(f)

    notifier = NotificationManager(config)
    notification_type = sys.argv[1]

    print(f"Testing {notification_type} notification...")
    result = notifier.test_notification(notification_type)

    if result:
        print(f"✓ {notification_type} notification sent successfully!")
        sys.exit(0)
    else:
        print(f"✗ {notification_type} notification failed")
        sys.exit(1)
