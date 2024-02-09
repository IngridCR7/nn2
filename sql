begin

DECLARE @CO_PERIODO INT = 202312

DROP TABLE IF EXISTS #TablaInicial
SELECT CO_PERIODO,CodSIGA, CodFuncion,Función,GS_ES,SISTEMA_VARIABLE,MODELO_VARIABLE,case when SFTotalTeoMes =0 then SueldoFijo else SFTotalTeoMes end SFTotalTeoMes,Area
,CAST(0 AS MONEY)PUL_ANUAL
,CAST(0 AS MONEY)PAU_IP_ANUAL
,CAST(0 AS MONEY)BXD_ANUAL
,CAST(0 AS MONEY)CTA_ANUAL
,CAST(0 AS MONEY)CTA_MENSUAL
,0 FL_ACTUALIZADO
,case when b.GS IN ('A4','A5') THEN 0
when b.GS like 'B%' THEN 0
when b.GS IN ('AS4','AS2') THEN 0
when b.GS like 'PS%' THEN 0
WHEN b.NIVEL <11 then 1 else 0.7 end  factor_icp,
Apellidos_Nombres
into #TablaInicial
--select *
FROM CONTROL_PROCESOS_COMP..HM_006_QUERY_SALARIAL a
left join WEB_IAS..NIVEL_GS b on a.GS_ES = b.GS
WHERE CO_PERIODO = @CO_PERIODO AND Flag_Organico = 1 
AND Estado = 'A' AND CodFuncion > 0 and GS_ES not like 'G%' AND GS_ES NOT IN ('S1','AS1')
AND SISTEMA_VARIABLE IN ('PAU','Inc Prod Trimestral','SCF Tipo B','INC PROD ANUAL','Comisiones','REM VARIABLE') and SueldoFijo > 0

DROP TABLE IF EXISTS #tablaPromGS
SELECT CO_PERIODO,GS_ES,SISTEMA_VARIABLE,AVG(SFTotalTeoMes)SFT,COUNT(*)HC 
INTO #tablaPromGS
FROM #TablaInicial G
GROUP BY CO_PERIODO,GS_ES,SISTEMA_VARIABLE

--se actualizan todos los sueldos
update a 
set a.SFTotalTeoMes = b.SFT
from #TablaInicial a
inner join #tablaPromGS b on a.GS_ES = b.GS_ES and a.SISTEMA_VARIABLE = b.SISTEMA_VARIABLE and a.CO_PERIODO = b.CO_PERIODO

--actualizando PAU SCF TIPO B // SE AGREGO EL 0.7 COMO FACTOR
UPDATE A
SET  A.PUL_ANUAL = CAST((B.ns_pul *  SFTotalTeoMes * factor_icp) AS money)
	,A.PAU_IP_ANUAL = CAST((B.ns_pau *  SFTotalTeoMes * factor_icp) AS money)
	,A.BXD_ANUAL = CAST((B.ns_bxd *  SFTotalTeoMes * factor_icp) AS money)
	,A.FL_ACTUALIZADO = 1	
FROM #TablaInicial a
left join greportes.tablaICPFija b on a.GS_ES = b.GS_ES
where a.SISTEMA_VARIABLE in( 'PAU','SCF Tipo B') AND A.FL_ACTUALIZADO = 0

DROP TABLE IF EXISTS #tablaIP
SELECT a.*
,c.factor_dias * 256 + factor_remuneracion * (cast((b.prom_ip_ppto+14)*SFT as money)) PUL
,cast((b.prom_ip_ppto * SFT) as money)prom_ip_ppto
into #tablaIP
FROM #tablaPromGS a
left join greportes.tablaIPTA b on a.GS_ES = b.GS_ES and a.SISTEMA_VARIABLE = b.SISTEMA_VARIABLE
--left join greportes.factorespul c on a.co_periodo / 100 - 1 = c.anio_ejercicio
left join CONTROL_PROCESOS_COMP.DataICP.tblFactoresPUL c on  c.anio_ejercicio = (select max(anio_ejercicio) from CONTROL_PROCESOS_COMP.DataICP.tblFactoresPUL)
where a.SISTEMA_VARIABLE in( 'Inc Prod Anual','Inc Prod Trimestral')
order by 2,1


--ACTUALIZANO IPT y IPA
UPDATE A
SET  A.PUL_ANUAL = CAST((B.PUL * factor_icp) AS money)
	,A.PAU_IP_ANUAL = CAST((b.prom_ip_ppto * factor_icp) AS money)
	,A.FL_ACTUALIZADO = 1
FROM #TablaInicial a
left join #tablaIP b on a.GS_ES = b.GS_ES AND A.SISTEMA_VARIABLE = B.SISTEMA_VARIABLE
where a.SISTEMA_VARIABLE in( 'Inc Prod Anual','Inc Prod Trimestral') AND A.FL_ACTUALIZADO = 0

--select a.*,(Prom_Comisiones_Vac + Prom_Remvar_Vac) variable
--,((SFTotalTeoMes + Prom_Comisiones_Vac + Prom_Remvar_Vac) * 14 )
--,c.f_dias * 256 + f_remuneracion * (cast((((SFTotalTeoMes + Prom_Comisiones_Vac + Prom_Remvar_Vac) * 14 )) as money)) PUL
--,c.f_dias * 256 + f_remuneracion * (cast((((SFTotalTeoMes + Prom_Comisiones_Vac + Prom_Remvar_Vac) * 14 )) as money))  + (cast((((SFTotalTeoMes + Prom_Comisiones_Vac + Prom_Remvar_Vac) * 14 )) as money)) CTAAnual
--from #TablaInicial a
--inner join BCP_GDH_COMP_STAGE..T_COMPENSACIONES_TOTAL b on a.CodSIGA = b.Nro_Personal and a.CO_PERIODO = b.Anio_Nomina * 100 + b.Mes_Nomina 
--left join greportes.factorespul c on a.co_periodo + 1 = c.co_periodo
--where (Prom_Comisiones_Vac + Prom_Remvar_Vac) > 0 and a.SISTEMA_VARIABLE in ('Comisiones','REM VARIABLE')


DROP TABLE IF EXISTS #tablaPeriodos
DECLARE @ID_TIEMPO INT  = (SELECT ID_TIEMPO FROM COMPENSACION_TOTAL..MM_TIEMPO WHERE CO_PERIODO = @CO_PERIODO)
SELECT CO_PERIODO INTO #tablaPeriodos FROM COMPENSACION_TOTAL..MM_TIEMPO WHERE ID_TIEMPO BETWEEN @ID_TIEMPO - 6 AND @ID_TIEMPO - 1

DROP TABLE IF EXISTS #tablaProm6MRV
SELECT NRO_PERSONAL,COUNT(DISTINCT B.CO_PERIODO) MESES
,SUM(Comisiones + Rem_Variable + Prom_Remvar_Vac +Prom_Comisiones_Vac+Prom_Comis_Subsi+Prom_RV_Ventas_Subsi+
Prom_RVMC_Subsi+Compl_RMV) AS VARIABLE_TOTAL_REAL 
INTO #tablaProm6MRV
FROM BCP_GDH_COMP_STAGE..T_COMPENSACIONES_TOTAL A
INNER JOIN #tablaPeriodos B ON (A.Anio_Nomina * 100 + A.Mes_Nomina ) = B.CO_PERIODO
inner join BCP_GDH_COMP_STAGE..T_ESTRUCTURA_SALARIAL c on a.Anio_Nomina = c.Anio_Nomina and a.Mes_Nomina = c.Mes_Nomina and a.Cod_Funcion = c.Id_Funcion_SAP
where c.Sistema_Variable in ('Comisiones','REM VARIABLE')
group by NRO_PERSONAL

DROP TABLE IF EXISTS #tblPromxMV
select MODELO_VARIABLE,SISTEMA_VARIABLE,(sum(b.VARIABLE_TOTAL_REAL) / sum(meses)) prom_rv_mensual ,count(distinct a.CodSIGA )colab,sum(MESES)meses,sum(b.VARIABLE_TOTAL_REAL)variable
into  #tblPromxMV
from #TablaInicial a
inner join #tablaProm6MRV b on a.CodSIGA = b.Nro_Personal
where a.SISTEMA_VARIABLE in ('Comisiones','REM VARIABLE')
group by MODELO_VARIABLE,SISTEMA_VARIABLE

--actualiza los mensuales
UPDATE A
SET  A.PUL_ANUAL = CAST((c.factor_dias * 256 + factor_remuneracion * ((SFTotalTeoMes + b.prom_rv_mensual) * 14 * factor_icp) ) AS money)
	,A.PAU_IP_ANUAL = CAST((b.prom_rv_mensual * 12) AS money)
	,A.FL_ACTUALIZADO = 1
FROM #TablaInicial a
left join #tblPromxMV b on a.MODELO_VARIABLE = b.MODELO_VARIABLE AND A.SISTEMA_VARIABLE = B.SISTEMA_VARIABLE
--left join greportes.factorespul c on a.co_periodo/100 - 1 = c.anio_ejercicio
--left join greportes.factorespul c on  c.anio_ejercicio = (select max(anio_ejercicio) from greportes.factorespul)
left join CONTROL_PROCESOS_COMP.DataICP.tblFactoresPUL c on  c.anio_ejercicio = (select max(anio_ejercicio) from CONTROL_PROCESOS_COMP.DataICP.tblFactoresPUL)
where a.SISTEMA_VARIABLE in ('Comisiones','REM VARIABLE') AND A.FL_ACTUALIZADO = 0

update a
set a.PUL_ANUAL = b.PUL_ANUAL, a.PAU_IP_ANUAL = b.PAU_IP_ANUAL,a.BXD_ANUAL = b.BXD_ANUAL,a.FL_ACTUALIZADO = 1
from #TablaInicial a
inner join (select GS_ES,SISTEMA_VARIABLE,avg(PUL_ANUAL)PUL_ANUAL,avg(PAU_IP_ANUAL)PAU_IP_ANUAL,avg(BXD_ANUAL)BXD_ANUAL from #TablaInicial where FL_ACTUALIZADO = 1 group by GS_ES,SISTEMA_VARIABLE )b 
on a.GS_ES = b.GS_ES and a.SISTEMA_VARIABLE = b.SISTEMA_VARIABLE
where a.FL_ACTUALIZADO = 0


update #TablaInicial set CTA_ANUAL = PUL_ANUAL + PAU_IP_ANUAL +BXD_ANUAL + 12*SFTotalTeoMes
update #TablaInicial set CTA_MENSUAL = CTA_ANUAL / 12
--update #TablaInicial set SISTEMA_VARIABLE = case when SISTEMA_VARIABLE in ('PAU','SCF Tipo B') then 'REM FIJA' WHEN SISTEMA_VARIABLE in ('Ninguno') THEN 'Ninguno' ELSE 'REM VARIABLE' END

select A.CO_PERIODO,A.CodSIGA,A.GS_ES,A.SISTEMA_VARIABLE,A.MODELO_VARIABLE,CAST(A.CTA_MENSUAL AS INT) Monto 
,CASE WHEN ISNULL(B.FL_CCHH,0) >0 THEN 'Sí' else 'No' end FL_CCHH
,CASE WHEN ISNULL(B.FL_CTS,0) >0 THEN 'Sí' else 'No' end FL_CTS into ##base_cta_
--select *
from #TablaInicial A
LEFT JOIN CONTROL_PROCESOS_COMP..HM_021_CCHH_CTS_BCP B ON A.CodSIGA = B.NU_PERSONAL AND A.CO_PERIODO = B.CO_PERIODO
where FL_ACTUALIZADO = 1 --and CodSIGA='636238'
ORDER BY GS_ES,SISTEMA_VARIABLE,MODELO_VARIABLE

end
