CREATE TABLE `balancer` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) NOT NULL DEFAULT '',
  `value` varchar(500) NOT NULL,
  `op_time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_key_balancer_key` (`key`),
  KEY `balancer_k_idx` (`key`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8;

CREATE TABLE `balancer_url` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `host` varchar(500) DEFAULT NULL,
  `port` int(11) NOT NULL DEFAULT '8080',
  `down` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `weight` smallint(10) unsigned NOT NULL DEFAULT '0',
  `max_fails` smallint(10) DEFAULT NULL,
  `fail_timeout` smallint(10) unsigned NOT NULL DEFAULT '0' COMMENT 'max_fails次失败后，暂停的时间',
  `backup` tinyint(1) NOT NULL DEFAULT '0',
  `status` tinyint(1) NOT NULL DEFAULT '1' COMMENT '状态1正常0删除',
  `b_id` int(11) NOT NULL,
  `created_time` int(10) DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `balancer_bid_idx` (`b_id`)
) ENGINE=InnoDB AUTO_INCREMENT=61 DEFAULT CHARSET=utf8;

CREATE TABLE `balancer_servers` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `ip` varchar(15) NOT NULL DEFAULT '0',
  `host_name` varchar(255) NOT NULL DEFAULT '0',
  `create_time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;