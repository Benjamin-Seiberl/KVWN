/** All valid Landesbewerb competition types with their display labels. */
export const BEWERB_TYPEN = [
	{ key: 'einzel_ak_herren',        label: 'Einzel AK Herren'        },
	{ key: 'einzel_ak_damen',         label: 'Einzel AK Damen'         },
	{ key: 'nachwuchs_u10_maennlich', label: 'Nachwuchs U10 männlich'  },
	{ key: 'nachwuchs_u10_weiblich',  label: 'Nachwuchs U10 weiblich'  },
	{ key: 'nachwuchs_u15_maennlich', label: 'Nachwuchs U15 männlich'  },
	{ key: 'nachwuchs_u15_weiblich',  label: 'Nachwuchs U15 weiblich'  },
	{ key: 'nachwuchs_u19_maennlich', label: 'Nachwuchs U19 männlich'  },
	{ key: 'nachwuchs_u19_weiblich',  label: 'Nachwuchs U19 weiblich'  },
	{ key: 'nachwuchs_u23_maennlich', label: 'Nachwuchs U23 männlich'  },
	{ key: 'nachwuchs_u23_weiblich',  label: 'Nachwuchs U23 weiblich'  },
	{ key: 'ue50_herren',             label: 'Ü50 Herren'              },
	{ key: 'ue50_damen',              label: 'Ü50 Damen'               },
	{ key: 'ue60_herren',             label: 'Ü60 Herren'              },
	{ key: 'ue60_damen',              label: 'Ü60 Damen'               },
	{ key: 'lm_sprint_herren',        label: 'LM Sprint Herren'        },
	{ key: 'lm_sprint_damen',         label: 'LM Sprint Damen'         },
	{ key: 'tandem_mixed',            label: 'Tandem Mixed'            },
];

/** Fast key→label lookup: BEWERB_LABEL['einzel_ak_herren'] === 'Einzel AK Herren' */
export const BEWERB_LABEL = Object.fromEntries(BEWERB_TYPEN.map(b => [b.key, b.label]));
