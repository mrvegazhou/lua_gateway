CREATE TABLE `limiting_rate` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) NOT NULL,
  `value` varchar(500) NOT NULL,
  `op_time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `limiting_rate_identifier` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `condition_value` varchar(255) NOT NULL,
  `create_time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `type_value` varchar(255) NOT NULL,
  `type` tinyint(1) NOT NULL DEFAULT '1' COMMENT '1:consumer,2:credential,3:ip,4:URI,5:Query,6:Header,7:UserAgent,8:Method,9:Referer,10:host',
  `period` int(5) NOT NULL DEFAULT '0',
  `rule_id` int(11) NOT NULL,
  `condition` varchar(10) NOT NULL DEFAULT '=',
  `period_count` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `limiting_rate_type_identifier_idx` (`type`,`condition`,`condition_value`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8;
alter table `limiting_rate_identifier` add index limiting_rate_type_identifier_idx (`type`, `condition`, `condition_value`);

