
<!DOCTYPE html>
<html>
    <head>
        <#include "../header.ftl">
        <#include "../chosen.ftl">
        <link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/handsontable-pro@latest/dist/handsontable.full.min.css">
        <link rel="stylesheet" type="text/css" href="/stylesheets/toggle/bootstrap-toggle.min.css" />
        <script>
            let wbObj;
            let spsContainer;
            let spreadsheet;
            let curSheetName;
            let templates = {};
            let fileName;
            let workbook;
            let userVarMap = {};
            let icasaVarMap = {
                "management" : {
                    <#list icasaMgnVarMap?values?sort_by("code_display")?sort_by("group")?sort_by("subset")?sort_by("dataset") as var>
                    "${var.code_display}" : {
                        code_display : "${var.code_display}",
                        description : '${var.description}',
                        unit_or_type : "${var.unit_or_type}",
                        dataset : "${var.dataset}",
                        subset : "${var.subset}",
                        group : "${var.group}",
                        agmip_data_entry : "${var.agmip_data_entry}",
                        category : "${var.dataset} / ${var.subset} / ${var.group}"
                    }<#sep>,</#sep>
                    </#list>
                },
                "observation" : {
                    <#list icasaObvVarMap?values?sort_by("code_display")?sort_by("group")?sort_by("subset")?sort_by("dataset") as var>
                    "${var.code_display}" : {
                        code_display : "${var.code_display}",
                        description : "${var.description}",
                        unit_or_type : "${var.unit_or_type}",
                        dataset : "${var.dataset}",
                        subset : "${var.subset}",
                        group : "${var.group}",
                        agmip_data_entry : "${var.agmip_data_entry}",
                        category : "${var.dataset} / ${var.subset} / ${var.group}"
                    }<#sep>,</#sep>
                    </#list>
                },
                "getPrimaryGroup" : function(varName) {
                    if (this.management[varName]) {
                        return this.management;
                    } else if (this.observation[varName]) {
                        return this.observation;
                    } else {
                        return null;
                    }
                },
                "getDefinition" : function(varName) {
                    let group = this.getPrimaryGroup(varName);
                    if (group) {
                        return group[varName];
                    } else {
                        return null;
                    }
                    
                },
                "getUnit" : function(varName) {
                    let group = this.getPrimaryGroup(varName);
                    if (group) {
                        return group[varName].unit_or_type;
                    } else {
                        return null;
                    }
                }
            };
            
            function getFileName(fileFullName) {
                if (!fileFullName) {
                    return fileFullName;
                }
                let lastDot = fileFullName.lastIndexOf(".");
                if (lastDot < 0) {
                    return fileFullName;
                } else {
                    return fileFullName.substring(0, lastDot);
                }
            }
            
            function readSpreadSheet(target, sc2Files) {
                let files = target.files;
                let f = files[0];
                fileName = getFileName(f.name);
                userVarMap = {};
                curSheetName = null;
                let reader = new FileReader();
                reader.onload = function(e) {
                    let data = e.target.result;
//                    data = new Uint8Array(data);
                    workbook = XLSX.read(data, {type: 'binary'});
                    if (sc2Files.files && sc2Files.files.length > 0) {
                        readSC2Json(sc2Files);
                    } else {
                        showSheetDefDialog(processData);
                    }
                };
                reader.readAsBinaryString(f);
            }
            
            function processData(ret) {
                if (ret) templates = ret;
                if (workbook) {
                    $("#sheet_csv_content").html(to_csv(workbook));
//                        $("#sheet_json_content").html(to_json(workbook));

                    wbObj = to_object(workbook);
                    $('#sheet_tab_list').empty();
                    for (let sheetName in templates) {
                        $('#sheet_tab_list').append('<li><a data-toggle="tab" href="#spreadshet_tab" id="' + sheetName + '" onclick="setSpreadsheet(this);">' + sheetName + '</a></li>');
                    }
                    if (curSheetName) {
                        initSpreadsheet(curSheetName);
                    } else {
                        $('#sheet_tab_list').find("a").first().click();
                    }
                }
            }
            
            function to_json(workbook) {
                return JSON.stringify(to_object(workbook), 2, 2);
            }
            
            function to_object(workbook) {
                let result = {};
                workbook.SheetNames.forEach(function(sheetName) {
                    if (!templates[sheetName]) {
                        return;
                    }
                    if (curSheetName && sheetName !== curSheetName) {
                        result[sheetName] = wbObj[sheetName];
                        return;
                    }
                    let roa = XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], {header:1, raw: false});
                    let sheetDef = templates[sheetName];
                    if (roa.length) {
                        if (roa.length > 0) {
                            // store sheet data
                            let headers;
                            if (sheetDef.header_row) {
                                headers = roa[sheetDef.header_row - 1];
                            } else {
                                headers = [];
                            }
                            result[sheetName] = {};
                            result[sheetName].header = headers;
                            result[sheetName].data = roa;

                            // init template structure
                            if (!sheetDef.mappings || curSheetName) {
                                sheetDef.mappings = [];
                                for (let i = 0; i < headers.length; i++) {
                                    let headerDef = {
                                        column_header : headers[i],
                                        column_index : i + 1
                                    };
                                    if (sheetDef.unit_row) {
                                        headerDef.unit = roa[sheetDef.unit_row - 1][i];
                                    }
                                    if (sheetDef.desc_row) {
                                        headerDef.description = roa[sheetDef.desc_row - 1][i];
                                    }
                                    let headerName = String(headerDef.column_header).toUpperCase();
                                    if (icasaVarMap.getDefinition(headerName)) {
                                        headerDef.icasa = headerName;
                                    } else if (icasaVarMap.getDefinition(headerDef.column_header)) {
                                        headerDef.icasa = headerDef.column_header;
                                    }
                                    if (headerDef.icasa) {
                                        let icasa_unit = icasaVarMap.getUnit(headerDef.icasa);
                                        if (headerDef.unit && headerDef.unit !== icasa_unit) {
                                            $.get(encodeURI("/data/unit/convert?unit_to=" + icasa_unit + "&unit_from="+ headerDef.unit + "&value_from=1"),
                                                function (jsonStr) {
                                                    let ret = JSON.parse(jsonStr);
                                                    if (ret.status !== "0") {
//                                                        headerDef.unit = icasa_unit; // TODO this should change to give warning message
                                                        headerDef.unit_error = true;
                                                    }
                                                }
                                            );
                                        } else if (!headerDef.unit) {
                                            headerDef.unit = icasa_unit;
                                        }
                                    }
                                    sheetDef.mappings.push(headerDef);
                                }
                                for (let i in roa) {
                                    while (sheetDef.mappings.length < roa[i].length) {
                                        sheetDef.mappings.push({column_index : sheetDef.mappings.length});
                                    }
                                }
                            } else {
                                // Load existing template definition and do unit convertion
                                // TODO
                            }
                        }
                    }
                });
                return result;
            }
            
            function to_csv(workbook) {
                let result = [];
                workbook.SheetNames.forEach(function(sheetName) {
                    var csv = XLSX.utils.sheet_to_csv(workbook.Sheets[sheetName], {raw: false});
                    if(csv.length){
                        result.push("SHEET: " + sheetName);
                        result.push("");
                        result.push(csv);
                    }
                });
                return result.join("\n");
            }
            
            function setSpreadsheet(target) {
                $("#sheet_name_selected").text(" <" + target.id + ">");
                curSheetName = target.id;
            }
            
            function initSpreadsheet(sheetName, spsContainer) {
                if (!spsContainer) {
                    spsContainer = document.querySelector('#sheet_spreadsheet_content');
                }
                if (spreadsheet) {
                    spreadsheet.destroy();
                }
                let minRows = 10;
                let data = wbObj[sheetName].data;
                let sheetDef = templates[sheetName];
                let mappings = sheetDef.mappings;
                let columns = [];
                for (let i in mappings) {
                    if (mappings[i].unit === "date") {
                        columns.push({type: 'date'});
                    } else if (mappings[i].unit === "text" || mappings[i].unit === "code") {
                        columns.push({type: 'text'});
                    } else if (mappings[i].unit !== ""){
                        columns.push({type: 'numeric'});
                    } else {
                        columns.push({type: 'text'});
                    }
                }
                for (let i in data) {
                    while (columns.length < data[i].length) {
                        columns.push({type: 'text'});
                    }
                }

                let spsOptions = {
                    licenseKey: 'non-commercial-and-evaluation',
                    data: data,
                    columns: columns,
                    stretchH: 'all',
//                    width: 500,
                    autoWrapRow: true,
//                    height: 450,
                    minRows: minRows,
                    maxRows: 365 * 30,
                    manualRowResize: true,
                    manualColumnResize: true,
                    rowHeaders: function (row) {
                        let txt;
                        if (row === sheetDef.header_row - 1) {
                            txt = "<span data-toggle='tooltip' title='Header (Varible Code Name)'><Strong>Var</Strong></span>";
                        } else if (row === sheetDef.unit_row - 1) {
                            txt = "<span data-toggle='tooltip' title='Unit Expression'><Strong>Unit</Strong></span>";
                        } else if (row === sheetDef.desc_row - 1) {
                            txt = "<span data-toggle='tooltip' title='Description/Definition'><Strong>Desc</Strong></span>";
                        } else if (!sheetDef.data_start_row) {
                            return row + 1;
                        } else if (row < sheetDef.data_start_row - 1) {
                            txt = "<span data-toggle='tooltip' title='Comment/Ignored raw'><em>C</em></span>";;
                        } else {
                            txt = row - sheetDef.data_start_row + 2;
                        }
                        return txt;
                    },
                    colHeaders: function (col) {
                        let checkBox = '<input type="checkbox" name="' + sheetName + '_' + col + '"';
                        if (mappings[col] && mappings[col].ignored_flg) {
                            checkBox += 'onchange=toggleIgnoreColumn(' + col + ');> ';
                        } else {
                            checkBox += 'checked onchange=toggleIgnoreColumn(' + col + ');> ';
                        }
//                        let colIdx = " <span class='badge'>" + (col + 1) + "</span>";
                        let colIdx = col + 1;
                        let title = "<span name='" + sheetName + '_' + col + "_label" + "' class='";
                        if (mappings[col] && mappings[col].ignored_flg) {
                            title += "label label-default'>" + mappings[col].column_header + " [" + colIdx + "]";
                        } else if (!mappings[col] || !mappings[col].column_header) {
                            title += "label label-warning'>" + colIdx;
//                        } else if (!mappings[col].icasa) {
//                            title += "label label-warning'>" + mappings[col].column_header + "[" + colIdx + "]";
                        } else if (mappings[col].icasa) {
                            let varDef = icasaVarMap.getDefinition(mappings[col].icasa);
                            if (varDef) {
                                if (mappings[col].unit_error) {
                                    title += "label label-danger' data-toggle='tooltip' title='<" + mappings[col].icasa + "> " + varDef.description + " [" + varDef.unit_or_type + "]'>[" + colIdx + "] ";
                                } else {
                                    title += "label label-success' data-toggle='tooltip' title='<" + mappings[col].icasa + "> " + varDef.description + " [" + varDef.unit_or_type + "]'>[" + colIdx + "] ";
                                }
                                if (mappings[col].icasa.toLowerCase() !== mappings[col].column_header.toLowerCase()) {
                                   title += "<em>" +  mappings[col].column_header + "->" + mappings[col].icasa + "</em> ";
                                } else {
                                    title += mappings[col].column_header;
                                }
                                if (mappings[col].unit.toLowerCase() !== varDef.unit_or_type.toLowerCase()) {
                                    title += "<br/><em>[" + varDef.unit_or_type + "->" + mappings[col].unit + "]</em>"
                                } else {
//                                    title += " [" + varDef.unit_or_type + "]'>";
                                }
                                
                            } else {
                                title += "label label-info' data-toggle='tooltip' title='<" + mappings[col].icasa + "> " + mappings[col].description + " [" + mappings[col].unit + "]'>[" + colIdx + "] " + mappings[col].column_header ;
                            }
                        } else {
                            title += "label label-warning'>[" + colIdx + "] " + mappings[col].column_header;
                        }
                        title += "</span>";
                        
                        return "<h4>" + checkBox + title + "</h4>";
                    },
//                    headerTooltips: true,
//                    afterChange: function(changes, src) {
//                        if(changes){
//                            
//                        }
//                    },
                    manualRowMove: false,
                    manualColumnMove: false,
                    filters: true,
                    dropdownMenu: true,
                    contextMenu: {
                        items: {
                            "new_column":{
                                name: "New Column",
                                hidden: function () { // `hidden` can be a boolean or a function
                                    // Hide the option when the first column was clicked
//                                    return this.getSelectedLast()[1] == 0; // `this` === hot3
                                    return true;
                                },
                                callback: function(key, selection, clickEvent) {
                                    setTimeout(function() {
                                        alertBox("Functionality under construction...");
                                    }, 0); // Fire alert after menu close (with timeout)
                                }
                            },
                            "define_column":{
                                name: "Define Column",
                                disabled: function () {
                                    // disable the option when the multiple columns were selected
                                    let range = this.getSelectedLast();
                                    let selection = this.getSelected();
                                    return range[1] !== range[3] || selection.length !== 1;
                                },
                                callback: function(key, selection, clickEvent) {
                                    setTimeout(function() {
                                        let data = {};
                                        let colIdx = selection[0].start.col;
//                                        data.column_header = spreadsheet.getColHeader(data.colIdx);
                                        let colDef = templates[curSheetName].mappings[colIdx];
                                        Object.assign(data, colDef);
                                        showColDefineDialog(data);
                                    }, 0); // Fire alert after menu close (with timeout)
                                }
                            },
                            "ignore_column":{
                                name: "Ignore Column",
                                hidden: function () { // `hidden` can be a boolean or a function
                                    // Hide the option when it is ignored
                                    let selection = this.getSelected();
                                    for (let i in selection) {
                                        for (let j = selection[i][1]; j <= selection[i][3]; j++) {
                                            if ($("[name='" + curSheetName + "_" + j + "']").last().prop("checked")) {
                                                return false;
                                            }
                                        }
                                    }
                                    return true;
                                },
                                callback: function(key, selection, clickEvent) {
                                    setTimeout(function() {
                                        for (let i in selection) {
                                            for (let j = selection[i].start.col; j <= selection[i].end.col; j++) {
                                                let cb = $("[name='" + curSheetName + "_" + j + "']").last();
                                                cb.prop("checked", false).trigger("change");
                                            }
                                        }
                                    }, 0); // Fire alert after menu close (with timeout)
                                }
                            },
                            "include_column":{
                                name: "Include Column",
                                hidden: function () { // `hidden` can be a boolean or a function
                                    // Hide the option when it is ignored
                                    let selection = this.getSelected();
                                    for (let i in selection) {
                                        for (let j = selection[i][1]; j <= selection[i][3]; j++) {
                                            if (!$("[name='" + curSheetName + "_" + j + "']").last().prop("checked")) {
                                                return false;
                                            }
                                        }
                                    }
                                    return true;
                                },
                                callback: function(key, selection, clickEvent) {
                                    setTimeout(function() {
                                        for (let i in selection) {
                                            for (let j = selection[i].start.col; j <= selection[i].end.col; j++) {
                                                let cb = $("[name='" + curSheetName + "_" + j + "']").last();
                                                cb.prop("checked", true).trigger("change");
                                            }
                                        }
                                    }, 0); // Fire alert after menu close (with timeout)
                                }
                            },
                            "edit_row":{
                                name: "Edit Row Definition",
                                callback: function(key, selection, clickEvent) {
                                    setTimeout(function() {
                                        showSheetDefDialog(processData, null, true);
                                    }, 0); // Fire alert after menu close (with timeout)
                                }
                            },
//                            "sep2": '---------',
//                            "row_above": {},
//                            "row_below": {},
//                            "remove_row": {},
//                            "sep1": '---------',
//                            "undo": {},
//                            "redo": {},
//                            "cut": {},
//                            "copy": {},
//                            "clear":{
//                                name : "clear",
//                                callback: function(key, selection, clickEvent) { // Callback for specific option
//                                    setTimeout(function() {
//                                        alertBox('Hello world!'); // Fire alert after menu close (with timeout)
//                                    }, 0);
//                                }}
                        }
                    }
                };
                if (!$('#tableViewSwitch').prop("checked")) {
                    spsOptions.data = spsOptions.data.slice(sheetDef.data_start_row - 1);
                    spsOptions.rowHeaders = true;
                }
                spreadsheet = new Handsontable(spsContainer, spsOptions);
                if ($('#tableViewSwitch').prop("checked")) {
                    spreadsheet.updateSettings({
                        cells: function(row, col, prop) {
                            var cell = spreadsheet.getCell(row,col);
                            if (!cell) {
                                return;
                            }
                            if (row === sheetDef.header_row - 1) {
    //                            cell.style.color = "white";
    //                            cell.style.fontWeight = "bold";
                                cell.style.fontStyle = "italic";
                                cell.style.backgroundColor = "lightgrey";
                                return {readOnly : true};
                            } else if (row === sheetDef.unit_row - 1) {
    //                            cell.style.color = "white";
    //                            cell.style.textDecoration = "underline";
                                cell.style.fontStyle = "italic";
                                cell.style.backgroundColor = "lightgrey";
                                return {readOnly : true};
                            } else if (row === sheetDef.desc_row - 1) {
    //                            cell.style.color = "white";
                                cell.style.fontStyle = "italic";
                                cell.style.backgroundColor = "lightgrey";
                                return {readOnly : true};
                            } else if (row < sheetDef.data_start_row - 1) {
    //                            cell.style.color = "white";
                                cell.style.backgroundColor = "lightgrey";
                                return {readOnly : true};
                            }
                        },
                    });
                }
                $('.table_switch_cb').bootstrapToggle('enable');
                if (!sheetDef.data_start_row) {
                    $('#tableViewSwitch').bootstrapToggle('disable');
                }
            }

            function toggleIgnoreColumn(colIdx) {
                if ($("[name='" + curSheetName + "_" + colIdx + "']").last().prop("checked")) {
                    delete templates[curSheetName].mappings[colIdx].ignored_flg;
                    $("[name='" + curSheetName + "_" + colIdx + "_label']").last().attr("class", getColStatusClass(colIdx));
                } else {
                    templates[curSheetName].mappings[colIdx].ignored_flg = true;
                    $("[name='" + curSheetName + "_" + colIdx + "_label']").last().attr("class", "label label-default");
                }
            }
            
            function getColStatusClass(col) {
                let sheetDef = templates[curSheetName];
                let mappings = sheetDef.mappings;
                if (mappings[col]) {
                    if (mappings[col].ignored_flg) {
                        return "label label-default";
                    } else if (mappings[col].icasa) {
                        if (icasaVarMap.getDefinition(mappings[col].icasa)) {
                            return "label label-success";
                        } else {
                            return "label label-info";
                        }
                    }
                }
                return "label label-warning";
            }
            
            function convertUnit() {
                // TODO
            }
            
            function openExpDataFile() {
                showLoadFileDialog();
            }
            
            function openExpDataFolderFile() {
                alertBox("Functionality under construction...");
            }
            
            function saveExpDataFile() {
                alertBox("Functionality under construction...");
            }
            
            function saveAcebFile() {
                alertBox("Functionality under construction...");
            }
            
            function openTemplateFile() {
                if (!workbook) {
                    alertBox("Please load spreadsheet file first, then apply SC2 file for it.");
                } else {
                    $('<input type="file" accept=".sc2.json,.json,.sc2" onchange="readSC2Json(this);">').click();
                }
            }

            function readSC2Json(target) {
                templates = {};
                var files = target.files;
                if (files.length !== 1) {
                    alertBox('Please select one file!');
                    return;
                }
                var file = files[0];
                var start = 0;
                var stop = file.size - 1;
                var reader = new FileReader();
                reader.onloadend = function (evt) {
                    if (evt.target.readyState === FileReader.DONE) { // DONE == 2
                        var jsonStr = evt.target.result;
//                        readSoilData(jsonStr);
                        
                        var sc2Obj = JSON.parse(jsonStr);
                        $(".mapping_gengeral_info").val("");
                        if (sc2Obj.mapping_info) {
                            for (let key in sc2Obj.mapping_info) {
                                $("[name='" + key + "']").val(sc2Obj.mapping_info[key]);
                            }
                        }
                        if (sc2Obj.agmip_translation_mappings) {
                            if (sc2Obj.agmip_translation_mappings.length === 0) {
                                alertBox("No AgMIP mapping information detected, please try another file!");
                                return;
                            }
                            // Locate the correct file for reading mappings
                            let fileConfig;
                            for (let i in sc2Obj.agmip_translation_mappings) {
                                fileConfig = sc2Obj.agmip_translation_mappings[i];
                                if (fileConfig.file && fileConfig.file.file_metadata
                                        && fileName === fileConfig.file.file_metadata.file_name) {
                                    break;
                                } else {
                                    fileConfig = null;
                                }
                            }
                            // If no matched file name, then use first defition as default
                            if (!fileConfig) {
                                fileConfig = sc2Obj.agmip_translation_mappings[0];
                            }
                            
                            if (!fileConfig.file.sheets) {
                                fileConfig.file.sheets = [];
                            }
                            // Load mapping for each sheet and fill missing column with ignore flag
                            for (let i in fileConfig.file.sheets) {
                                let sheetName = fileConfig.file.sheets[i].sheet_name;
                                if (!sheetName) sheetName = "" + i;
                                templates[sheetName] = Object.assign({}, fileConfig.file.sheets[i]);
                                if (!templates[sheetName].header_row) {
                                    templates[sheetName].header_row = 1;
                                }
                                if (!templates[sheetName].data_start_row) {
                                    templates[sheetName].data_start_row = templates[sheetName].header_row + 1;
                                }
                                let sc2Mappings = fileConfig.file.sheets[i].mappings;
                                let mappings = templates[sheetName].mappings;
                                mappings = [];
                                let curIdx = 0;
                                for (let j in sc2Mappings) {
                                    let colIdx = Number(sc2Mappings[j].column_index);
                                    for (let k = curIdx; k < colIdx; k++) {
                                        if (!mappings[k]) {
                                            mappings.push({
                                                column_index : k,
                                                ignored_flg : true
                                            });
                                        }
                                    }
                                    if (mappings[colIdx]) {
                                        mappings[colIdx] = sc2Mappings[j];
                                    } else {
                                        mappings.push(sc2Mappings[j]);
                                    }
                                }
                            }
                            processData();
                        }
                    }
                };

                var blob = file.slice(start, stop + 1);
                reader.readAsBinaryString(blob);
            }
            
            function saveTemplateFile() {
                if (!fileName) {
                    alertBox("Please load spreadsheet file first, then edit and save SC2 file for it.");
                } else {
                    let text = toSC2Json();
                    let ext = "-sc2.json";
                    let blob = new Blob([text], {type: "text/plain;charset=utf-8"});
                    saveAs(blob, fileName + ext);
                }
            }
            
            function toSC2Json(compressFlg) {
                if (compressFlg) {
                    return JSON.stringify(toSC2Obj());
                } else {
                    return JSON.stringify(toSC2Obj(), 2, 2);
                }
            }
            
            function toSC2Obj() {
                let sc2Obj = {
                    mapping_info : {
//                        mapping_author : "data factory (http://dssat2d-plot.herokuapp.com/demo/data_factory)",
//                        source_url: ""
                    },
                    dataset_metadata : {},
                    agmip_translation_mappings : [
                        {
                            relations : [],
                            //Grab the primary keys from here if EXNAME is not defined
                            primary_ex_sheet : {
    //                            file : "",
    //                            sheet : "" 
                            },
                            file : {
                                file_metadata : {
                                    file_name : fileName,
                                    "content-type" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                                    // file_url : ""
                                },
                                sheets : []
                            }
                        }
                    ],
                    xrefs : [
//                        {
//                          xref_provider : "gardian",
//                          xref_url : "https://gardian.bigdata.cgiar.org/dataset.php?id=5cd88b72317da7f1ae0cf390#!/"
//                        }
                    ]
                };
                
                $(".mapping_gengeral_info").each(function () {
                   sc2Obj.mapping_info[$(this).attr("name") ] = $(this).val();
                });
                
                for (let sheetName in templates) {
                    let tmp = Object.assign({}, templates[sheetName]);
                    tmp.mappings = [];
                    for (let i in templates[sheetName].mappings) {
                        if (!templates[sheetName].mappings[i].ignored_flg) {
                            tmp.mappings.push(templates[sheetName].mappings[i]);
                        }
                    }
                    sc2Obj.agmip_translation_mappings[0].file.sheets.push(tmp);
                }
                return sc2Obj;
            }
            
            function alertBox(msg, callback) {
                if (callback) {
                    bootbox.alert({
                        message: msg,
                        backdrop: true,
                        callback: callback
                    });
                } else {
                    bootbox.alert({
                        message: msg,
                        backdrop: true
                    });
                }
                
            }
        </script>
    </head>

    <body>

        <#include "../nav.ftl">

        <div class="container"></div>
        <div class="container-fluid">
            <div class="">
                <div class="btn-group">
                    <button type="button" class="btn btn-primary dropdown-toggle" data-toggle="dropdown">
                        Experiment Data <span class="caret"></span>
                    </button>
                    <ul class="dropdown-menu" role="menu">
                        <li onclick="openExpDataFile()" id="openFileMenu"><a href="#"><span class="glyphicon glyphicon-open"></span> Load file</a></li>
                        <li onclick="openExpDataFolderFile()"><a href="#"><span class="glyphicon glyphicon-open"></span> Load folder</a></li>
                        <li onclick="saveExpDataFile()"><a href="#"><span class="glyphicon glyphicon-save"></span> Save</a></li>
                        <li onclick="saveAcebFile()"><a href="#"><span class="glyphicon glyphicon-export"></span> To Aceb</a></li>
                    </ul>
                </div>
                <div class="btn-group">
                    <button type="button" class="btn btn-primary dropdown-toggle" data-toggle="dropdown">
                        Template <span class="caret"></span>
                    </button>
                    <ul class="dropdown-menu" role="menu">
                        <li onclick="openTemplateFile()"><a href="#"><span class="glyphicon glyphicon-open"></span> Load Existed Template</a></li>
                        <li onclick="saveTemplateFile()"><a href="#"><span class="glyphicon glyphicon-save"></span> Save Template</a></li>
                    </ul>
                </div>
<!--                <button type="button" class="btn btn-primary" onclick="openFile()"><span class="glyphicon glyphicon-open"></span> Load</button>
                <button type="button" class="btn btn-primary" onclick="saveFile()"><span class="glyphicon glyphicon-save"></span> Save</button>-->
            </div>
            <br/>
            <ul class="nav nav-tabs">
                <li id="sheetTab" class="active dropdown">
                    <a class="dropdown-toggle" data-toggle="dropdown" href="#">Spreadsheet
                        <span id="sheet_name_selected"></span>
                        <span class="caret"></span>
                    </a>
                    <ul class="dropdown-menu" id="sheet_tab_list">
                    </ul>
                </li>
                <li><a data-toggle="tab" href="#general_tab">General Info</a></li>
                <li id="SC2Tab"><a data-toggle="tab" href="#sc2_tab">SC2 Preview</a></li>
                <li><a data-toggle="tab" href="#csv_tab"><em> CSV [debug]</em></a></li>
                <li id="mappingTab"><a data-toggle="tab" href="#mapping_tab"><em>Mappings Cache [debug]</em></a></li>
            </ul>
            <div class="tab-content">
                <div id="spreadshet_tab" class="tab-pane fade in active">
                    <div class="">
    <!--                        <span class="label label-info"><strong>&nbsp;Header Row&nbsp;</strong></span>
                            <span class="label label-info"><u>&nbsp;&nbsp;&nbsp;&nbsp;Unit Row&nbsp;&nbsp;&nbsp;&nbsp;</u></span>
                            <span class="label label-info"><em>Description Row</em></span>
                            <span class="label label-default">Ignored Row</span>-->
                        <label>View Style: </label>
                        <input type="checkbox" id="tableViewSwitch" class="table_switch_cb" data-toggle="toggle" data-size="mini" data-on="Full View" data-off="Data Only">
                        <label>Column Marker : </label>
                        <span class="label label-success">ICASA Mapped</span>
                        <span class="label label-info">Customized</span>
                        <span class="label label-warning">Undefined</span>
                        <span class="label label-danger"><em>Warning</em></span>
                        <span class="label label-default">Ignored</span>
<!--                        <input type="checkbox" id="tableColSwitchSuccess" class="table_switch_cb" data-toggle="toggle" data-size="mini" data-on="Show" data-off="Hide" data-onstyle="success" checked>
                        <input type="checkbox" id="tableColSwitchWarning" class="table_switch_cb" data-toggle="toggle" data-size="mini" data-on="Show" data-off="Hide" data-onstyle="warning" checked>
                        <input type="checkbox" id="tableColSwitchDanger" class="table_switch_cb" data-toggle="toggle" data-size="mini" data-on="Show" data-off="Hide" data-onstyle="danger" checked>
                        <input type="checkbox" id="tableColSwitchInfo" class="table_switch_cb" data-toggle="toggle" data-size="mini" data-on="Show" data-off="Hide" data-onstyle="info" checked>-->
                    </div>
                    <div id="sheet_spreadsheet_content" class="col-sm-12"></div>
                </div>
                <div id="csv_tab" class="tab-pane fade">
                    <textarea class="form-control" rows="30" id="sheet_csv_content" style="font-family:Consolas,Monaco,Lucida Console,Liberation Mono,DejaVu Sans Mono,Bitstream Vera Sans Mono,Courier New, monospace;" readonly></textarea>
                </div>
                <div id="general_tab" class="tab-pane fade">
                    <div class="subcontainer">
                        <div class="form-group col-sm-12">
                            <label class="control-label">Mapping Author Email:</label>
                            <div class="input-group col-sm-12">
                                <input type="email" name="mapping_author" class="form-control mapping_gengeral_info" value="">
                            </div>
                        </div>
                        <div class="form-group col-sm-12">
                            <label class="control-label">Oringal Data URL:</label>
                            <div class="input-group col-sm-12">
                                <input type="url" name="source_url" class="form-control mapping_gengeral_info" value="">
                            </div>
                        </div>
                    </div>
                </div>
                <div id="mapping_tab" class="tab-pane fade">
                    <textarea class="form-control" rows="30" id="mapping_json_content" style="font-family:Consolas,Monaco,Lucida Console,Liberation Mono,DejaVu Sans Mono,Bitstream Vera Sans Mono,Courier New, monospace;" readonly></textarea>
                </div>
                <div id="sc2_tab" class="tab-pane fade">
                    <textarea class="form-control" rows="30" id="sc2_json_content" style="font-family:Consolas,Monaco,Lucida Console,Liberation Mono,DejaVu Sans Mono,Bitstream Vera Sans Mono,Courier New, monospace;" readonly></textarea>
                </div>
            </div>
        </div>

        <#include "data_factory_popup_loadFile.ftl">
        <#include "data_factory_popup_row.ftl">
        <#include "data_factory_popup_column.ftl">
        <#include "../footer.ftl">
        <script type="text/javascript" src='/plugins/FileSaver/FileSaver.js'></script>
        <script type="text/javascript" src="/js/sheetjs/shim.js" charset="utf-8"></script>
        <script type="text/javascript" src="/js/sheetjs/xlsx.full.min.js"></script>
        <script type="text/javascript" src="/plugins/filestyle/bootstrap-filestyle.min.js"></script>
        <script type="text/javascript" src="/plugins/chosen/chosen.jquery.min.js" ></script>
        <script type="text/javascript" src="/plugins/chosen/prism.js" charset="utf-8"></script>
        <script type="text/javascript" src="/js/chosen/init.js" charset="utf-8"></script>
        <script type="text/javascript" src="/js/dataReader/BufferedFileReader.js"></script>
        <script type="text/javascript" src="/js/bootbox/bootbox.all.min.js" charset="utf-8"></script>
        <script type="text/javascript" src="/js/toggle/bootstrap-toggle.min.js" charset="utf-8"></script>
        <script src="https://cdn.jsdelivr.net/npm/handsontable@6.2.2/dist/handsontable.full.min.js"></script>
        
        <script>
            $(document).ready(function () {
                initIcasaLookupSB();
                chosen_init_all();
                $('input').on("blur", function(event) {
                    event.target.checkValidity();
                }).bind('invalid', function(event) {
                    alertBox(event.target.value + " is an invalid " + event.target.type, function () {
                        setTimeout(function() { $(event.target).focus();}, 50);
                    });
                });
                $('.nav-tabs #sheetTab').on('shown.bs.tab', function(){
                    $('.table_switch_cb').bootstrapToggle('enable');
                    if (templates[curSheetName].data_start_row) {
//                        initSpreadsheet(curSheetName);
                        $('#tableViewSwitch').bootstrapToggle('off');
                    } else {
                        $('#tableViewSwitch').bootstrapToggle('on');
                    }
                });
                $('.nav-tabs #mappingTab').on('shown.bs.tab', function(){
                    $("#mapping_json_content").html(JSON.stringify(templates, 2, 2));
                });
                $('.nav-tabs #SC2Tab').on('shown.bs.tab', function(){
                    $("#sc2_json_content").html(toSC2Json());
                });
                $("button").prop("disabled", false);
                $('#tableViewSwitch').change(function () {
                    initSpreadsheet(curSheetName);
                });
//                $('#tableColSwitchSuccess').change(function () {
//                    let plugin = spreadsheet.getPlugin('hiddenColumns');
//                    let hiddenArr = [];
//                    let isShown = $('#tableColSwitchSuccess').prop('checked');
//                    let sheetDef = templates[curSheetName];
//                    let mappings = sheetDef.mappings;
//                    for (let i = 0; i < mappings.length; i++) {
//                        if (mappings[i].icasa) {
//                            if (isShown) {
//                                plugin.showColumn(i);
//                            } else {
//                                plugin.hideColumn(i);
//                            }
//                            
//                        }
//                    };
//                });
                $('.table_switch_cb').bootstrapToggle('disable');
                $("#openFileMenu").click();
            });
        </script>
    </body>
</html>

