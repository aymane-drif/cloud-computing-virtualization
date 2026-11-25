<ossec_config>

  <client>
    <server>
      <address>__MANAGER__</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
    <crypto_method>aes</crypto_method>
    <notify_time>10</notify_time>
    <time-reconnect>60</time-reconnect>
    <auto_restart>yes</auto_restart>
    <enrollment>
      <enabled>yes</enabled>
      <manager_address>__MANAGER__</manager_address>
      <port>1515</port>
      <agent_name>__AGENT_NAME__</agent_name>
      <authorization_pass_path>etc/authd.pass</authorization_pass_path>
    </enrollment>
  </client>

  <!-- Journaux systeme : scenarios 1, 2 et 4 -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/syslog</location>
  </localfile>

  <!-- Application metier, chemin nominal.
       log_format json : Wazuh decode nativement, aucun decodeur n'est ecrit
       pour ce fichier. Chaque cle devient un champ interrogeable. -->
  <localfile>
    <log_format>json</log_format>
    <location>/var/log/app-metier/access.json</location>
  </localfile>

  <!-- Application metier, mode degrade : c'est ce fichier la que notre
       decodeur local_decoder.xml prend en charge. -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/app-metier/access.log</location>
  </localfile>

  <!-- Controle d'integrite : scenario 3.
       realtime="yes" est obligatoire. En mode periodique, l'alerte n'arrive
       qu'au prochain cycle et on conclut a tort que la detection ne marche pas. -->
  <syscheck>
    <disabled>no</disabled>
    <frequency>300</frequency>
    <scan_on_start>yes</scan_on_start>
    <alert_new_files>yes</alert_new_files>
    <directories check_all="yes" realtime="yes">/usr/local/bin</directories>
    <directories check_all="yes" realtime="yes">/etc</directories>
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/resolv.conf</ignore>
    <ignore>/etc/adjtime</ignore>
  </syscheck>

  <rootcheck>
    <disabled>yes</disabled>
  </rootcheck>

  <logging>
    <log_format>plain</log_format>
  </logging>

</ossec_config>
