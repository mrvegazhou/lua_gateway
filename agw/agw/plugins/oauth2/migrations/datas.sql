CREATE TABLE `oauth2_credentials` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL DEFAULT '',
  `consumer_id` int(11) unsigned NOT NULL,
  `client_id` int(11) unsigned NOT NULL,
  `client_secret` varchar(500) NOT NULL DEFAULT '',
  `redirect_uri` varchar(1000) NOT NULL DEFAULT '',
  `created_time` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '创建或者更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_client_secret` (`client_secret`),
  UNIQUE KEY `unique_client_id` (`client_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE `oauth2_credentials` ADD INDEX oauth2_credentials_consumer_idx ( `consumer_id` );
ALTER TABLE `oauth2_credentials` ADD INDEX oauth2_credentials_client_idx ( `client_id` );
ALTER TABLE `oauth2_credentials` ADD INDEX oauth2_credentials_secret_idx ( `client_secret` );


CREATE TABLE `oauth2_authorization_codes` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(500) NOT NULL DEFAULT '',
  `authenticated_userid` int(11) unsigned NOT NULL,
  `scope` varchar(1000) NOT NULL DEFAULT '',
  `created_time` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '创建或者更新时间',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE `oauth2_authorization_codes` ADD INDEX oauth2_autorization_code_idx ( `code` );
ALTER TABLE `oauth2_authorization_codes` ADD INDEX oauth2_authorization_userid_idx ( `authenticated_userid` );

CREATE TABLE oauth2_tokens(
        `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
        `credential_id`  int(11) unsigned NOT NULL,
        `access_token` varchar(255) NOT NULL DEFAULT '',
        `token_type` TINYINT(1) NOT NULL DEFAULT 1,
        `refresh_token` varchar(255) NOT NULL DEFAULT '',
        `expires_in` int(11) unsigned NOT NULL,
        `authenticated_userid` int(11) unsigned NOT NULL,
        `scope`  varchar(500) NOT NULL DEFAULT '',
        `created_time` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '创建或者更新时间',
        PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8; 

ALTER TABLE `oauth2_tokens` ADD INDEX oauth2_accesstoken_idx ( `access_token` );
ALTER TABLE `oauth2_tokens` ADD INDEX oauth2_token_refresh_idx ( `refresh_token` );
ALTER TABLE `oauth2_tokens` ADD INDEX oauth2_token_userid_idx ( `authenticated_userid` );