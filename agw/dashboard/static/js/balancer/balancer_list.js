(function (L) {
    var _this = null;
    L.Balancer = L.Balancer || {};
    _this = L.Balancer = {
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
            _this.initAddInfo();
            _this.initShowConsulCatalogServices();
        },

        initGetData: function(obj) {
            var url_id = $(obj).attr('data-id');
            var c_info;
            var info_tmp = $.ajax({url: "/api/balancer/urls", async:false, method:'post', data:{url_id:url_id}}).responseJSON;
            if( info_tmp.success==true ) {
                c_info = info_tmp.data.info;
            } else {
                L.Common.showErrorTip("提示", "获取授权信息异常");
                return false;
            }
            return c_info;
        },

        initShowInfo: function(){
            $(document).on("click", ".info-btn", function () {
                var c_info = _this.initGetData(this);
                var tpl = $("#edit-tpl").html();
                var html = juicer(tpl, {info:c_info[0]});
                var d = dialog({
                    title: '详情',
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

        initShowConsulCatalogServices: function(){
            $(document).on("click", "#view-consul-info", function () {
                var consul_infos = $.ajax({url: "/api/balancer/consul_infos", async:false, method:'post', data:{} }).responseJSON;
                var html = '';
                if(consul_infos.success==true) {
                    $.each(consul_infos.data.services_list, function (i, ele){
                        html += ele+'<br/>'                      
                    });
                } else {
                    html = "数据错误";
                }
                console.log(html);
                var d = dialog({
                    title: 'Consul Catalog Services列表',
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
                var obj = $(this);
                var c_info = _this.initGetData(this);
                var tpl = $("#edit-tpl").html();
                var html = juicer(tpl, {info:c_info[0]});
                var d = dialog({
                    title: '编辑',
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
                            var tmp_host = $("#host").val();
                            var tmp_port = $("#port").val();
                            var tmp_weight = $("#weight").val();
                            var tmp_max_fails = $("#max_fails").val();
                            var tmp_fail_timeout = $("#fail_timeout").val();
                            var tmp_down = $("#down").val();
                            var tmp_backup = $("#backup").val();
                            var ex = /^\d+$/;
                            if(!ex.test(tmp_port)) {
                                L.Common.showTipDialog("错误提示", "端口必须为整型");
                                return false;
                            }
                            if(!ex.test(tmp_weight)) {
                                L.Common.showTipDialog("错误提示", "权重必须为整型");
                                return false;
                            }
                            if(!ex.test(tmp_max_fails)) {
                                L.Common.showTipDialog("错误提示", "最大错误次数必须为整型");
                                return false;
                            }
                            $.ajax({
                                url: '/api/balancer/urls',
                                type: 'put',
                                cache:false,
                                data: { url_id:c_info[0].id,
                                        tmp_host:tmp_host, 
                                        tmp_port:tmp_port, 
                                        tmp_weight:tmp_weight, 
                                        tmp_max_fails:tmp_max_fails, 
                                        tmp_fail_timeout:tmp_fail_timeout, 
                                        tmp_down:tmp_down, 
                                        tmp_backup:tmp_backup
                                },
                                dataType: 'json',
                                success: function (result) {
                                    if (result.success) {
                                        obj.parent().siblings().each(function(idx, ele) {
                                            var tmp_str = ($(ele).attr('id')).split("_");
                                            var arr = result.data;
                                            $(ele).html(arr[tmp_str[1]]);
                                        });
                                        L.Common.showTipDialog("提示", "修改成功");
                                        return true;
                                    } else {
                                        if(result.msg) {
                                            L.Common.showTipDialog("错误提示", result.msg);
                                        } else {
                                            L.Common.showTipDialog("错误提示", "修改负载url配置请求发生错误");
                                        }
                                        return false;
                                    }
                                },
                                error: function (jqXHR, textStatus, errorThrown) {
                                    //console.log(jqXHR.responseText, textStatus, errorThrown);
                                    L.Common.showTipDialog("提示", "修改负载url配置请求发生异常");
                                    return false;
                                }
                            });
                        }
                    }]
                });
                d.show();   
            })
        },

        initDelInfo: function(){
            $(document).on("click", ".del-info-btn", function () {
                var obj = $(this);
                var url_id = $(this).attr('data-id');
                var d = dialog({
                    title: '提示',
                    width: 400,
                    content: "确定要删除吗？",
                    modal: true,
                    button: [{
                        value: '取消'
                    }, {
                        value: '确定',
                        autofocus: false,
                        callback: function () {
                            $.ajax({
                                url: "/api/balancer/urls",
                                type: 'delete',
                                cache:false,
                                data: {
                                    url_id: url_id
                                },
                                dataType: 'json',
                                success: function (result) {
                                    if (result.success) {
                                        //重新渲染规则
                                        (obj.parent().parent('tr')).remove();
                                        return true;
                                    } else {
                                        L.Common.showErrorTip("提示", result.msg || "删除错误");
                                        return false;
                                    }
                                },
                                error: function () {
                                    L.Common.showErrorTip("提示", "删除异常");
                                    return false;
                                }
                            });
                        }
                    }
                    ]
                });
                d.show();    
            })
        },

        initAddInfo: function(){
            $(document).on("click", "#add-info-btn", function () {
                var obj = $(this);
                var tpl = $("#edit-tpl").html();
                var html = juicer(tpl, {info:{}});
                var d = dialog({
                    title: '添加',
                    width: 700,
                    content: html,
                    modal: true,
                    button: [{
                        value: '取消'
                    },{
                        value: '添加',
                        autofocus: false,
                        id: 'add_btn_1',
                        callback: function () {
                            var tmp_host = $("#host").val();
                            var tmp_port = $("#port").val();
                            var tmp_weight = $("#weight").val();
                            var tmp_max_fails = $("#max_fails").val();
                            var tmp_fail_timeout = $("#fail_timeout").val();
                            var tmp_down = $("#down").val();
                            var tmp_backup = $("#backup").val();
                            var bid = $("#hid_bid").val();
                            if(bid=='') {
                                L.Common.showTipDialog("错误提示", "负载规则主键缺失");
                                return false;
                            } 
                            if(tmp_host=='') {
                                L.Common.showTipDialog("错误提示", "host不能为空");
                                return false;
                            }
                            var ex = /^\d+$/;
                            if(!ex.test(tmp_port)) {
                                L.Common.showTipDialog("错误提示", "端口必须为整型");
                                return false;
                            }
                            if(!ex.test(tmp_weight)) {
                                L.Common.showTipDialog("错误提示", "权重必须为整型");
                                return false;
                            }
                            if(!ex.test(tmp_max_fails)) {
                                L.Common.showTipDialog("错误提示", "最大错误次数必须为整型");
                                return false;
                            }
                            $.ajax({
                                url: '/api/balancer/addurl',
                                type: 'post',
                                cache:false,
                                data: { tmp_host:tmp_host, 
                                        tmp_port:tmp_port, 
                                        tmp_weight:tmp_weight, 
                                        tmp_max_fails:tmp_max_fails, 
                                        tmp_fail_timeout:tmp_fail_timeout, 
                                        tmp_down:tmp_down, 
                                        tmp_backup:tmp_backup,
                                        bid:bid
                                },
                                dataType: 'json',
                                success: function (result) {
                                    if (result.success) {
                                        L.Common.showTipDialog("提示", "添加成功");
                                        location.reload();
                                        return true;
                                    } else {
                                        if(result.msg) {
                                            L.Common.showTipDialog("错误提示", result.msg);
                                        } else {
                                            L.Common.showTipDialog("错误提示", "添加负载url配置请求发生错误");
                                        }
                                    }
                                },
                                error: function () {
                                    L.Common.showTipDialog("提示", "添加负载url配置请求发生异常");
                                }
                            });
                            return false;
                        }
                    }]
                });
                d.show();
            })
        }
    };
}(APP));