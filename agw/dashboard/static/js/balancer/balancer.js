(function (L) {
    var _this = null;
    L.Balancer = L.Balancer || {};
    _this = L.Balancer = {
        data: {
            rules: {}
        },

        init: function () {
            _this.loadConfigs();
            _this.initEvents();
            _this.syncServers();
            _this.clearServers();
        },

        initEvents: function () {
            L.Common.initRuleAddDialog("balancer", _this);//添加规则对话框
            L.Common.initRuleDeleteDialog("balancer", _this);//删除规则对话框
            L.Common.initSwitchBtn("balancer");//关闭、开启
            L.Common.initViewAndDownloadEvent("balancer");
            L.Common.pagerAjaxBtn('#rule-item-tpl', '#rules');
            L.Common.initRuleEditDialog("balancer", _this, '路由负载');//编辑对话框
        },

        loadConfigs: function (highlight_id) {
            $.ajax({
                url: '/api/balancer/list',
                type: 'get',
                cache:false,
                data: {},
                dataType: 'json',
                success: function (result) {
                    if (result.success) {
                        L.Common.resetSwitchBtn(result.data.enable, "路由负载");
                        $("#switch-btn").show();
                        $("#view-btn").show();
                        _this.renderTable(result.data, highlight_id);//渲染table
                        _this.data.enable = result.data.enable;
                        _this.data.rules = result.data.upstreams;//重新设置数据

                    } else {
                        L.Common.showTipDialog("错误提示", "查询路由负载配置请求发生错误");
                    }
                },
                error: function () {
                    L.Common.showTipDialog("提示", "查询路由负载配置请求发生异常");
                }
            });
        },

        renderTable: function (data, highlight_id) {
            var tpl = $("#rule-item-tpl").html();
            var html = juicer(tpl, data);
            $("#rules").html(html);
        },

        //判断规则条件
        buildRule: function () {
            var result = {
                success: false,
                data: {
                    key: null,
                    host: null,
                    balancer_type: {},
                    code: null,
                    log: null
                }
            };

            var key = $("#rule-key").val();
            if (!key) {
                result.success = false;
                result.data = "账户名称不能为空";
                return result;
            } else {
                result.data.key = key;
            }

            var host = $('#rule-host').val();
            if (!host) {
                result.success = false;
                result.data = "host名称不能为空";
                return result;
            } else {
                result.data.host = host;
            }

            var type_rr = $("#rule-balancer_type_rr").is(':checked');
            result.data.balancer_type.rr = type_rr;
            var type_q = $("#rule-balancer_type_quick").is(':checked');
            result.data.balancer_type.quick = type_q;

            var handle_code = $.trim($("#rule-code").val());
            var ex = /^\d+$/;
            var rule_log = $('#rule-log').val();
            if (!ex.test(handle_code) && rule_log=="true") {
                result.success = false;
                result.data = "未授权处理的状态码不能为空";
                return result;
            }
            result.data.code = parseInt(handle_code);
            result.data.log = (rule_log === "true");

            //enable or not
            var enable = $('#rule-enable').is(':checked');
            result.data.enable = enable;

            result.success = true;
            return result;
        },
        
        syncServers: function () {
            $("#sync-btn").click(function () {
                $.ajax({
                    url: '/api/balancer/sync_servers',
                    type: 'POST',
                    dataType: 'json',
                    success: function (result) {
                        if (result.success) {
                            L.Common.showTipDialog("提示", "同步成功<br/>"+result.data.servers);
                        } else {
                            L.Common.showTipDialog("错误提示", "同步错误");
                        }
                    },
                    error: function () {
                        L.Common.showTipDialog("错误提示", "同步异常");
                    }
                });
            });
        },

        clearServers: function () {
            $("#clear-btn").click(function () {
                $.ajax({
                    url: '/api/balancer/clear_servers',
                    type: 'POST',
                    dataType: 'json',
                    success: function (result) {
                        if (result.success) {
                            if(result.data.servers=='') {
                                L.Common.showTipDialog("提示", "无可清除servers");
                            } else {
                                L.Common.showTipDialog("提示", "清除成功<br/>"+result.data.servers);
                            }
                        } else {
                            L.Common.showTipDialog("错误提示", "清除错误");
                        }
                    },
                    error: function () {
                        L.Common.showTipDialog("错误提示", "清除异常");
                    }
                });
            });
        }
    };
}(APP));