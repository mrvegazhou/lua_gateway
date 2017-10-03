(function (L) {
    var _this = null;
    L.Oauth2 = L.Oauth2 || {};
    _this = L.Oauth2 = {
        data: {
            lists: {}
        },

        init: function () {
            _this.initEvents();
        },

        initEvents: function () {
            _this.initShowInfo();
            _this.initEditInfo();
            _this.initDelInfo();
            L.Common.initRuleEditDialog("oauth2", _this);//编辑规则对话框
            L.Common.initRuleDeleteDialog("oauth2", _this);//删除规则对话框
        },

        initGetData: function(obj) {
            var consumer_id = $(obj).attr('data-id');
            var info_tmp = $.ajax({url: "/api/oauth2/regedit", async:false, dataType: 'json', data: {consumer_id:consumer_id}, method:'POST'}).responseJSON;
            if( info_tmp.success==true ) {
                c_info = info_tmp.data.info;
                return c_info;
            } else {
                L.Common.showErrorTip("提示", "获取授权信息异常");
                return false;
            }
        },

        initShowInfo: function(){
            $(document).on("click", ".info-btn", function () {
                var c_info = _this.initGetData(this);
                var tpl = $("#edit-tpl").html();
                var html = juicer(tpl, {info:c_info});
                var d = dialog({
                    title: 'Oauth2账户认证详情',
                    width: 700,
                    content: html,
                    modal: true,
                    button: [{
                        value: '确认'
                    }]
                });
                d.show();
            })
        },

        initEditInfo: function(){
            $(document).on("click", ".edit-info-btn", function () {
                var c_info = _this.initGetData(this);
                var tpl = $("#edit-tpl").html();
                var html = juicer(tpl, {info:c_info});
                var d = dialog({
                    title: 'Oauth2账户认证编辑',
                    width: 700,
                    content: html,
                    modal: true,
                    button: [{
                        value: '取消'
                    },{
                        value: '编辑',
                        autofocus: false,
                        id: 'reg_btn_1',
                        callback: function () {
                            var init_password = $("#init_password").val();
                            var showname = $("#showname").val();
                            var client_secret = $("#client_secret").val();
                            var redirect_uri = $("#redirect_uri").val();
                            var access_token = $("#access_token").val();
                            var token_type = $("#token_type").val();
                            var refresh_token = $("#refresh_token").val();
                            var consumers_id = $("#consumers_id").val();
                            var expires_in = $("#expires_in").val();
                            var scope = $("#scope").val();
                            var redirect_uri = $("#redirect_uri").val();
                            $.ajax({
                                url: '/api/oauth2/editRegInfo',
                                type: 'post',
                                cache:false,
                                data: { consumers_id:consumers_id,
                                        expires_in:expires_in, 
                                        redirect_uri:redirect_uri, 
                                        init_password:init_password,
                                        showname:showname,
                                        client_secret:client_secret, 
                                        access_token:access_token, 
                                        token_type:token_type, 
                                        refresh_token:refresh_token,
                                        scope:scope },
                                dataType: 'json',
                                success: function (result) {
                                    if (result.success) {
                                        L.Common.showTipDialog("提示", "修改成功");
                                        return true;
                                    } else {
                                        if(result.msg) {
                                            L.Common.showTipDialog("错误提示", result.msg);
                                        } else {
                                            L.Common.showTipDialog("错误提示", "查询Oauth2 Auth配置请求发生错误");
                                        }
                                        return false;
                                    }
                                },
                                error: function () {
                                    L.Common.showTipDialog("提示", "查询Oauth2 Auth配置请求发生异常");
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

        initDelInfo: function(){
            $(document).on("click", ".del-info-btn", function () {
                var obj = $(this);
                var consumer_id = $(this).attr('data-id');
                var d = dialog({
                    title: '提示',
                    width: 400,
                    content: "确定要删除账户信息吗？",
                    modal: true,
                    button: [{
                        value: '取消'
                    }, {
                        value: '确定',
                        autofocus: false,
                        callback: function () {
                            $.ajax({
                                url: "/api/oauth2/editRegInfo",
                                type: 'delete',
                                cache:false,
                                data: {
                                    consumer_id: consumer_id
                                },
                                dataType: 'json',
                                success: function (result) {
                                    if (result.success) {
                                        //重新渲染规则
                                        //context.loadConfigs();
                                        obj.parent().parent('tr').remove();
                                        return true;
                                    } else {
                                        L.Common.showErrorTip("提示", result.msg || "删除规则发生错误");
                                        return false;
                                    }
                                },
                                error: function () {
                                    L.Common.showErrorTip("提示", "删除规则请求发生异常");
                                    return false;
                                }
                            });
                        }
                    }
                    ]
                });
                d.show();    
            })
        }

    };
}(APP));