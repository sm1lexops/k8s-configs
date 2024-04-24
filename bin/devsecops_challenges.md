# DevSecOps Challenges

1.1 Настройка SSH: Напишите пример безопасной конфигурации SSH сервера для входящих подключений из внешней сети. 

> sshd configuration file

```sh
# меняем стандартный порт
Port 2233 
# по лучшим практикам используем статичные адреса, разрешаем только их 
ListenAddress 36.100.45.85

# отключаем вход от root
PermitRootLogin no

# разрешаем только определенным пользователям группам подключаться (при этом нужно создать пользователей, сгенерировать и разослать ключи  данных пользователей, пользователи должны прописать конфиг для подключения к ssh серверу 	~/.ssh/config :
Host <ssh-server>
    HostName <ssh_server_ip>
    User <username>
    IdentityFile ~/.ssh/id_rsa)

AllowUsers user1 user2
# AllowGroups sshusers

# отключаем вход по паролю и логину
PasswordAuthentication no

# включаем вход по публичному ключу
PubkeyAuthentication yes

# определяем директорию где храняться публичные ключи пользователей которые могут подключиться
AuthorizedKeysFile      .ssh/authorized_keys


# отключаем пустые пароли
PermitEmptyPasswords no

# (защищаемся от ddos) ставим лимит одновременных подключений 
MaxSessions 10

#(защищаемся от ddos) ставим ограничение одновременных подключений с 1 IP/процент не прошедших аутентификацию подключений (те 30% из 10 = 3 не аутентифицировано значит новые отбрасываем) / 60 время в секундах
MaxStartups 10:30:60

# вклюячаем реверс резолв ssh сервером клиента для защиты от спуфинга аутентификации
UseDNS yes

# включаем только ssh версии 2 протокол
Protocol 2

# определяем защищенные алгоритмы шифрования
Ciphers aes256-gcm@openssh.com, chacha20-poly1305@openssh.com, aes256-ctr, aes192-ctr, aes128-ctr
MACs hmac-sha2-256-etm@openssh.com, hmac-sha2-512-etm@openssh.com, hmac-sha2-256,hmac-sha2-512
KexAlgorithms curve25519-sha256@libssh.org, diffie-hellman-group-exchange-sha256

# ставим тайм-ауты проверки бездействия
LoginGraceTime 30s
ClientAliveInterval 300
ClientAliveCountMax 0

# отключаем форвардинг через данный сервер (при настройке в качестве сервера бастион включаем)
AllowTcpForwarding no
AllowAgentForwarding no

#мониторим логи подключений и попытки изменения в файловой системе полностью
LogLevel VERBOSE
SyslogFacility AUTH
Subsystem sftp  /usr/lib/ssh/sftp-server -f AUTHPRIV -l INFO

# определяем размещение ключей хоста
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# также опционально можем включить MFA от google, установив 
(apt) libpam-google-authenticator  (yam,dnf) google-authenticator

# добавляем правило для MFA
ChallengeResponseAuthentication yes
AuthenticationMethods publickey,keyboard-interactive
```

1.2 Напишите пример конфигурации SSH для bastion host (SSH jump server). Необходимо указать параметры, отличные от default.

Настройки для безопасного подключения пользователей выше оставляем и добавляем:

```sh
# отключаем форвардинг через данный сервер 
AllowTcpForwarding no
AllowAgentForwarding no
PermitTTY no
X11Forwarding no
PermitTunnel no
GatewayPorts no

# отключаем удаленное выполнение команд
ForceCommand /usr/sbin/nologin
```

Тестим подключение:

```sh
ssh -J <jump server> <remote server>
```

Для обеспечения безопасности при развертывании bastion сервера требуется дополнительно обратить внимание на следующие опции:

* Выбираем дистрибутив с минимальным содержанием предустановленных пакетов, программ, библиотек (например Debian minimal не имеет 3rd party components), это уменьшает возможную поверхность атак на данный сервер.
  
* Настраиваем фаервол компании (облака), а также внутренние сервисы OS iptables, SELinux для доступа только к порту SSH.
  
* При организации доступа в облачном окружении, настраиваем security groups, отключаем все не нужные сервисы в предустановленных дистрибутивах.
  
* Мониторим все! Настраиваем auditd сервера на передачу логов в систему SIEM (не храним локально), ELK, Wazuh agent.


2.1 Настройка политик безопасности Kubernetes: Напишите yaml, содержащий: Pod Security Admission (PSA) для указанного namespace. В случае нарушения политики модуль должен запускаться, но с добавлением примечания к событию в журнале аудита. 

```yaml
# определяем PSA на уровне кластера k8s
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1beta1
      kind: PodSecurityConfiguration
      defaults:
        enforce: "baseline"
        enforce-version: "latest"
        audit: "privileged"
        audit-version: "latest"
        warn: "privileged"
        warn-version: "latest"
      exemptions:
        usernames: []
        runtimeClasses: []
        namespaces: []
---
# либо на уровне namespace с помощью labels
apiVersion: v1
kind: Namespace
metadata:
  name: psa-privileged-namespace
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
---
apiVersion: v1
kind: Namespace
metadata:
  name: psa-baseline-namespace
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: baseline
    pod-security.kubernetes.io/warn-version: latest
---
apiVersion: v1
kind: Namespace
metadata:
  name: psa-restricted-namespace
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest

---
# также определяем что пишем в аудит c определенных namespaces
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - "RequestReceived"
rules:
  - level: Request
    resources:
      - group: "" # core API group
        resources: ["pods"]
    namespaces: ["psa-privileged-namespace"]
  - level: RequestResponse
    resources:
      - group: "" # core API group
        resources: ["pods"]
      - group: "apps"
        resources: ["daemonsets, deployments, replicasets, statefulsets"]
    namespaces: ["psa-restricted-namespace"]
    verbs: ["create", "update"]
  - level: Metadata
    resources:
      - group: ""
        resources: ["pods/log", "pods/status"]
    namespaces: ["psa-baseline-namespace"]
---
# создаем конфиг  ValidatingWebhookConfiguration при валидации запросов   будут добавляться аннотации к аудиту и начинаться с значения в поле имени - name: "psa-webhook.kubernetes.io"

apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: "psa-webhook.kubernetes.io"

webhooks:
# добавляемая аннотация к логам аудита
  - name: "core.psa-webhook.kubernetes.io"
    failurePolicy: Fail
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: ["psa-baseline-namespace, psa-privileged-namespace, psa-restricted-namespace"]
    rules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources:
          - namespaces
          - pods
    clientConfig:
      caBundle: "/path/to/ca.crt"
      service:
        namespace: "psa-privileged-namespace"
        name: "webhook"
    admissionReviewVersions: ["v1"]
    sideEffects: None
    timeoutSeconds: 5
# добавляемая аннотация к логам аудита
  - name: "apps.psa-webhook.kubernetes.io"
    # Non-enforcing resources can safely fail-open.
    failurePolicy: Ignore
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: ["psa-baseline-namespace, psa-privileged-namespace, psa-restricted-namespace"]
    rules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources:
          - daemonsets
          - deployments
          - replicasets
          - statefulsets
    clientConfig:
      caBundle: "/path/to/ca.crt"
      service:
        namespace: "psa-privileged-namespace"
        name: "webhook"
    admissionReviewVersions: ["v1"]
    sideEffects: None
    timeoutSeconds: 5
```

2.2 Network Policies для ограничения доступа между подами, включая разграничение по namespace и labels. Доступ к подам postgres разрешается по порту 5432 только от подов app01 из пространства имен prod. RBAC политику, разрешающую доступ к указанному namespace пользователю Admin с максимальными привилегиями, а пользователю Audit только на просмотр. 



3. Настройка Security as Code: Опишите порядок действий по интеграции GitLab SAST в GitLab CI/CD pipeline. Приведите пример необходимых конфигураций для определения целевых объектов сканирования, времени выполнения и получения уведомлений. 
4. Интеграция сканера уязвимостей (например, OpenVAS): Опишите сценарий интеграции, OpenVAS в GitLab CI/CD pipeline для автоматического сканирования уязвимостей в разрабатываемом приложении, действий по обработке результатов сканирования. Напишите пример yaml для GitLab CI/CD, содержащего скрипт по автоматизированному реагированию на обнаруженные уязвимости. 
5. Предложите схему интеграции Web Application Firewall (WAF) в инфраструктуре: Напишите конфигурацию для внедрения WAF (например, ModSecurity) в Nginx. Напишите конкретные примеры правил безопасности, которые вы бы применили в WAF (например, фильтрация SQL-инъекций, XSS-атак, блокировка заданных паттернов). 
6. Конфигурация ELK (EFK): Напишите конфигурацию агентов для сбора и анализа логов приложения в Kubernetes с использованием ELK. Приведите перечень основных событий, которые вы считаете важными для мониторинга информационной безопасности.
