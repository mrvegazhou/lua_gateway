(function (L) {
    var _this = null;
    L.Limiting_rate = L.Limiting_rate || {};
    _this = L.Limiting_rate = {
        data: {
            lists: {}
        },

        init: function () {
            _this.initEvents();
        },

        initEvents: function () {
            _this.initEditInfo();
            _this.initDelInfo();
            _this.initAddInfo();
        },

        initGetData: function(obj) {
            var info_id = $(obj).attr('data-id');
            var c_info;
            var info_tmp = $.ajax({url: "/api/limiting_rate/info", async:false, method:'post', data:{info_id:info_id}}).responseJSON;
            if( info_tmp.success==true ) {
                c_info = info_tmp.data.info;
            } else {
                L.Common.showErrorTip("提示", "获取授权信息异常");
                return false;
            }
            return c_info;
        },
        transformType: function(val) {
            var str = '';
            switch(parseInt(val)) {
                case 1:
                    str = 'API账户ID';
                    break;
                case 2:
                    str = '授权账户ID';
                    break;
                case 3:
                    str = 'IP';
                    break;
                case 4:
                    str = 'URI';
                    break;
                case 5:
                    str = 'Query';
                    break;
                case 6:
                    str = 'Header';
                    break;
                case 7:
                    str = 'UserAgent';
                    break;
                case 8:
                    str = 'Method';
                    break;
            }
            return str;
        },
        transformPeriod: function(val) {
            var str = '';
            switch(parseInt(val)) {
                case 1:
                    str = '1秒';
                    break;
                case 60:
                    str = '1分钟';
                    break;
                case 3600:
                    str = '1小时';
                    break;
                case 86400:
                    str = '1天';
                    break;
            }
            return str;
        },
        initEditInfo: function(){
            $(document).on("click", ".edit-info-btn", function () {
                var obj = $(this);
                var c_info = _this.initGetData(this);
                var tpl = $("#edit-tpl").html();
                console.log(c_info);
                var html = juicer(tpl, {info:c_info});
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
                            var rate_list_id = parseInt(obj.attr('data-id'));
                            if(rate_list_id=='') {
                                L.Common.showTipDialog("错误提示", "限速列表序号参数为空");
                                return false;
                            }

                            var rid = $("#hid_rid").val();
                            var ex = /^\d+$/;
                            var tmp_type = $("#edit_limit_type").val();
                            if(tmp_type=='') {
                                L.Common.showTipDialog("错误提示", "限速类型不能为空");
                                return false;
                            }
                            
                            var tmp_period_count = $("#edit_period_count").val();
                            if(tmp_period_count=='') {
                                L.Common.showTipDialog("错误提示", "限速次数不能为空");
                                return false;
                            }
                            if(!ex.test(tmp_period_count)) {
                                L.Common.showTipDialog("错误提示", "限速次数必须为整型");
                                return false;
                            }

                            var tmp_period = $("#edit_period").val();
                            if(tmp_period=='') {
                                L.Common.showTipDialog("错误提示", "时间类型不能为空");
                                return false;
                            }
                            if(-1==$.inArray(tmp_period, ["1", "60", "3600", "86400"])) {
                                L.Common.showTipDialog("错误提示", "请选择正确的时间类型");
                                return false;
                            }

                            var tmp_condition = $("#edit_condition").val();
                            if(tmp_condition=='') {
                                L.Common.showTipDialog("错误提示", "限制条件不能为空");
                                return false;
                            } 
                            if(-1==$.inArray(tmp_condition, ["match", "not_match", "=", "!=", ">", ">=", "≤"])) {
                                L.Common.showTipDialog("错误提示", "请选择正确的限制条件");
                                return false;
                            }
                            var tmp_condition_value = $("#edit_condition_value").val();
                            if(tmp_condition=='') {
                                L.Common.showTipDialog("错误提示", "限制条件值不能为空");
                                return false;
                            }
                            $.ajax({
                                url: '/api/limiting_rate/list',
                                type: 'put',
                                cache: false,
                                data: { tmp_type:tmp_type,
                                        tmp_period_count:tmp_period_count, 
                                        tmp_period:tmp_period,
                                        tmp_condition:tmp_condition, 
                                        tmp_condition_value:tmp_condition_value, 
                                        rid:rid,
                                        rate_list_id:rate_list_id
                                },
                                dataType: 'json',
                                success: function (result) {
                                    if (result.success) {
                                        obj.parent().siblings().each(function(idx, ele) {
                                            var tmp_str = ($(ele).attr('id')).split("-");
                                            var arr = result.data;
                                            if(tmp_str[1]=='type') {
                                                var type_str = _this.transformType(arr[tmp_str[1]]);
                                                $(ele).html(type_str);
                                            } else if(tmp_str[1]=='period') {
                                                var period_str = _this.transformPeriod(arr[tmp_str[1]]);
                                                $(ele).html(period_str);
                                            } else {
                                                $(ele).html(arr[tmp_str[1]]);
                                            }
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
                var rate_id = $(this).attr('data-id');
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
                                url: "/api/limiting_rate/list",
                                type: 'delete',
                                cache:false,
                                data: {
                                    rate_id: rate_id
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
                var tpl = $("#add-tpl").html();
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
                        callback: function () {
                            var rid = $("#hid_rid").val();
                            var ex = /^\d+$/;
                            var tmp_type = $("#limit_type").val();
                            if(tmp_type=='') {
                                L.Common.showTipDialog("错误提示", "限速类型不能为空");
                                return false;
                            }

                            var tmp_period_count = $("#period_count").val();
                            if(tmp_period_count=='') {
                                L.Common.showTipDialog("错误提示", "限速次数不能为空");
                                return false;
                            }
                            if(!ex.test(tmp_period_count)) {
                                L.Common.showTipDialog("错误提示", "限速次数必须为整型");
                                return false;
                            }

                            var tmp_period = $("#period").val();
                            if(tmp_period=='') {
                                L.Common.showTipDialog("错误提示", "时间类型不能为空");
                                return false;
                            }
                            if(-1==$.inArray(tmp_period, ["1", "60", "3600", "86400"])) {
                                L.Common.showTipDialog("错误提示", "请选择正确的时间类型");
                                return false;
                            }

                            var tmp_condition = $("#condition").val();
                            if(tmp_condition=='') {
                                L.Common.showTipDialog("错误提示", "限制条件不能为空");
                                return false;
                            } 
                            if(-1==$.inArray(tmp_condition, ["match", "not_match", "=", "!=", ">", ">=", "≤"])) {
                                L.Common.showTipDialog("错误提示", "请选择正确的限制条件");
                                return false;
                            }
                            var tmp_condition_value = $("#condition_value").val();
                            if(tmp_condition=='') {
                                L.Common.showTipDialog("错误提示", "限制条件值不能为空");
                                return false;
                            }
                            $.ajax({
                                url: '/api/limiting_rate/list',
                                type: 'post',
                                cache: false,
                                data: { tmp_type:tmp_type,
                                        tmp_period_count:tmp_period_count, 
                                        tmp_period:tmp_period,
                                        tmp_condition:tmp_condition, 
                                        tmp_condition_value:tmp_condition_value, 
                                        rid:rid
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
                                            L.Common.showTipDialog("错误提示", "添加限制条件请求发生错误");
                                        }
                                    }
                                },
                                error: function () {
                                    L.Common.showTipDialog("提示", "添加限制条件请求发生异常");
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