(function (L) {
    var _this = null;
    L.Oauth2 = L.Oauth2 || {};
    _this = L.Oauth2 = {
        data: {
            rules: {}
        },

        init: function () {
            _this.loadConfigs();
            _this.initEvents();
        },

        initEvents: function () {
            L.Common.initRuleAddDialog("oauth2", _this);//添加规则对话框
            L.Common.initRuleDeleteDialog("oauth2", _this);//删除规则对话框
            L.Common.initRuleEditDialog("oauth2", _this);//编辑规则对话框
            //L.Common.initSyncDialog("oauth2", _this);//

            L.Common.initConditionAddOrRemove();//添加或删除条件

            L.Common.initViewAndDownloadEvent("oauth2");
            L.Common.initSwitchBtn("oauth2");//oauth2关闭、开启

            _this.initShowOauth2Info();//显示验证信息
        },

        initShowOauth2Info: function() {
            $(document).on("click", ".auth-btn", function () {
                var rule_id = $(this).attr('data-id');
                var content = $("#auth-tpl").html();
                console.log(content);
                var d = dialog({
                    title: 'Oauth2认证',
                    width: 750,
                    content: content,
                    modal: true,
                    button: [{
                        value: '取消'
                    }, {
                        value: '注册授权',
                        autofocus: false,
                        id: 'reg_btn_1',
                        callback: function () {
                            var oauth2_username = $('#oauth2-username').val();
                            var oauth2_showname = $('#oauth2-showname').val();
                            var oauth2_redirect_uri = $('#oauth2-redirect_uri').val();
                            var oauth2_name = $('#oauth2-name').val();
                            var oauth2_scope = $('#oauth2-scope').val();
                            if($.trim(oauth2_username)=='') {
                                L.Common.showErrorTip("提示", "账户名称不能为空");return false;
                            }
                            $.ajax({
                                url:  "/api/oauth2/reg",
                                type: 'post',
                                cache: false,
                                data: {
                                    rule_id: rule_id,
                                    username: oauth2_username,
                                    showname: oauth2_showname,
                                    redirect_uri: oauth2_redirect_uri,
                                    name: oauth2_name,
                                    scope: oauth2_scope
                                },
                                dataType: 'json',
                                success: function (result) {
                                    if (result.success) {
                                        var str =   "access token:"+result.data.access_token+"<br/>"+
                                                    "token类型:"+result.data.token_type+"<br/>"+
                                                    "失效期限:"+result.data.expires_in+"<br/>"+
                                                    "权限范围:"+result.data.scope+"<br/>"+
                                                    "refresh token:"+result.data.refresh_token+"<br/>"+
                                                    "请求用户中心接口耗时:"+result.data.query_reg_execution_time
                                                    ;
                                        $("#auth-info-mgs").html(str);
                                        return true;
                                    } else {
                                        L.Common.showErrorTip("提示", result.msg || "授权发生错误");
                                        return false;
                                    }
                                },
                                error: function () {
                                    L.Common.showErrorTip("提示", "授权请求发生异常");
                                    return false;
                                }
                            });
                            return false;
                        }
                    }]
                });
                d.show();
            })
        },

        buildRule: function () {
            var result = {
                success: false,
                data: {
                    name: null,
                    handle: {}
                }
            };

            var name = $("#rule-name").val();
            if (!name) {
                result.success = false;
                result.data = "账户名称不能为空";
                return result;
            } else {
                result.data.name = name;
            }

            //build handle
            var buildHandleResult = _this.buildHandle();
            if (buildHandleResult.success == true) {
                result.data.handle = buildHandleResult.handle;
            } else {
                result.success = false;
                result.data = buildHandleResult.data;
                return result;
            }

            //enable or not
            var enable = $('#rule-enable').is(':checked');
            result.data.enable = enable;

            result.success = true;
            return result;
        },

        buildHandle: function () {
            var result = {};
            var handle = {};
            handle.credentials = {};
            var handle_token_expiration = $("#rule-handle-token_expiration").val();
            if(!handle_token_expiration) {
                result.success = false;
                result.data = "访问令牌失效时间不能为空";
                return result;
            } else {
                var ex = /^\d+$/;
                if(!ex.test(handle_token_expiration)) {
                    result.success = false;
                    result.data = "访问令牌失效时间必须为整数";
                    return result;
                } else {
                    handle.credentials.token_expiration = handle_token_expiration;
                }
            }

            var handle_enable_authorization_code = $("#rule-handle-enable_authorization_code").is(':checked');
            var handle_enable_client_credentials = $("#rule-handle-enable_client_credentials").is(':checked');
            var handle_enable_implicit_grant = $("#rule-handle-enable_implicit_grant").is(':checked');
            var handle_enable_password_grant = $("#rule-handle-enable_password_grant").is(':checked');
            if(!handle_enable_authorization_code && !handle_enable_client_credentials && !handle_enable_implicit_grant && !handle_enable_password_grant) {
                result.success = false;
                result.data = "验证方式不能为空";
                return result;
            } else {
                handle.credentials.enable_authorization_code = handle_enable_authorization_code;
                handle.credentials.enable_client_credentials = handle_enable_client_credentials;
                handle.credentials.enable_implicit_grant = handle_enable_implicit_grant;
                handle.credentials.enable_password_grant = handle_enable_password_grant;
            }

            handle.credentials.handle_hide_credentials = $("#rule-handle_hide_credentials").is(':checked');
            handle.credentials.handle_accept_http_if_already_terminated = $("#rule-handle_accept_http_if_already_terminated").is(':checked');

            var handle_code = $("#rule-handle-code").val();
            if (!handle_code) {
                result.success = false;
                result.data = "未授权处理的状态码不能为空";
                return result;
            }

            handle.code = parseInt(handle_code);

            handle.log = ($("#rule-handle-log").val() === "true");
            result.success = true;
            result.handle = handle;
            return result;
        },

        loadConfigs: function (highlight_id) {
            $.ajax({
                url: '/api/oauth2/configs',
                type: 'get',
                cache:false,
                data: {},
                dataType: 'json',
                success: function (result) {
                    if (result.success) {
                        L.Common.resetSwitchBtn(result.data.enable, "oauth2");
                        $("#switch-btn").show();
                        $("#view-btn").show();
                        _this.renderTable(result.data, highlight_id);//渲染table
                        _this.data.enable = result.data.enable;
                        _this.data.rules = result.data.rules;//重新设置数据

                    } else {
                        L.Common.showTipDialog("错误提示", "查询Oauth2 Auth配置请求发生错误");
                    }
                },
                error: function () {
                    L.Common.showTipDialog("提示", "查询Oauth2 Auth配置请求发生异常");
                }
            });
        },

        renderTable: function (data, highlight_id) {
            highlight_id = highlight_id || 0;
            var tpl = $("#rule-item-tpl").html();
            data.highlight_id = highlight_id;
            var html = juicer(tpl, data);
            $("#rules").html(html);
        }
    };
}(APP));