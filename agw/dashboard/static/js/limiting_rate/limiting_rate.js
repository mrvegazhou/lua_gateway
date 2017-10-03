(function (L) {
    var _this = null;
    L.Limiting_rate = L.Limiting_rate || {};
    _this = L.Limiting_rate = {
        data: {
            rules: {}
        },

        init: function () {
            _this.loadConfigs();
            _this.initEvents();
        },

        initEvents: function () {
            L.Common.initRuleAddDialog("limiting_rate", _this);//添加规则对话框
            L.Common.initRuleDeleteDialog("limiting_rate", _this);//删除规则对话框
            L.Common.initRuleEditDialog("limiting_rate", _this, "限速");//编辑规则对话框

            // L.Common.initConditionAddOrRemove();//添加或删除条件

            L.Common.initViewAndDownloadEvent("limiting_rate");
            L.Common.initSwitchBtn("limiting_rate");//limiting_rate关闭、开启
        },

        buildRule: function () {
            var result = {
                success: false,
                data: {
                    key: null,
                    handle: {}
                }
            };

            var key = $("#rule-key").val();
            if (!key) {
                result.success = false;
                result.data = "规则名称不能为空";
                return result;
            } else {
                result.data.key = key;
            }

            var global_limit = $("#rule-global_limit").val();
            result.data.handle.global_limit =  (global_limit === "true"); 

            //enable or not
            var enable = $('#rule-enable').is(':checked');
            result.data.enable = enable;

            var handle_code = $.trim($("#rule-code").val());
            var ex = /^\d+$/;
            var rule_log = $('#rule-log').val();
            if (!ex.test(handle_code) && rule_log=="true") {
                result.success = false;
                result.data = "状态码不能为空";
                return result;
            }
            result.data.handle.code = parseInt(handle_code);
            result.data.handle.log = (rule_log === "true");

            result.success = true;
            return result;
        },

        loadConfigs: function (highlight_id) {
            $.ajax({
                url: '/api/limiting_rate/configs',
                type: 'get',
                cache: false,
                dataType: 'json',
                success: function (result) {
                    if (result.success) {
                        L.Common.resetSwitchBtn(result.data.enable, "限速");
                        $("#switch-btn").show();
                        $("#view-btn").show();
                        _this.renderTable(result.data, highlight_id);//渲染table
                        _this.data.enable = result.data.enable;
                        _this.data.rules = result.data.rules;//重新设置数据

                    } else {
                        L.Common.showTipDialog("错误提示", "查询限速配置请求发生错误");
                    }
                },
                error: function () {
                    L.Common.showTipDialog("提示", "查询限速配置请求发生异常");
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