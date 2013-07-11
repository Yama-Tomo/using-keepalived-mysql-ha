KeepAlivedでMySQLを冗長化させる
=====================
　
　2台のMySQLサーバをKeepAlivedを使って冗長化させます。
　それぞれのDBにマスター用のVIPとスレーブ用のVIPを設定し、
　どちらのサーバが故障してもアプリケーションからはマスタースレーブ
　両方見えるようにします。
　
  [[/Yama-Tomo/using-keepalived-mysql-ha/doc/overview.png]]

　メリットはMHAやMMMのように管理ノードを立てる新たに構築する必要がない点にあります。
　　
　3台以上DBサーバがある場合はMHAやMMMなどのソリューションを使った方がいいですし管理も楽です。
　

環境
======================

OS

* Ubuntu 12.04.1 LTS

MySQL

*  5.5.28

KeepAlived

*  1.2.2

M/Wに関しては手抜きでパッケージインストールです。
MySQLはSemi-sync replicationが前提なので5.5を入れました。

設定
======================

マスターDB

* hostname: DB-NODE1
* ip: 192.168.162.10
* master vip: 192.168.162.100

スレーブDB

* hostname: DB-NODE2
* ip: 192.168.162.20
* slave vip: 192.168.162.200


KeepAlived

　vrrp_instanceをmaster用、slave用それぞれ2つ定義します。

　デフォルトでは
　DB-NODE1にmaster VIPのインスタンスが`MASTER state`に、
　DB-NODE2にslave VIPのインスタンスが`MASTER state`になるように設定します。

  [[/Yama-Tomo/using-keepalived-mysql-ha/doc/overview.png]]
　
　また、master VIPのインスタンスが`MASTER state`のノードはマスター昇格用の
　スクリプトが実行されるように`norify_master`を設定します。
　
　また、自動でフェイルバックしないように **nopreempt** を設定します。

MySQL

　特に特殊な設定はしていません。通常のレプリケーションができるように設定をします。
　Semi-sync replicationは `my.cnf` で設定せずに `SET GLOBAL` で設定する形にします。

